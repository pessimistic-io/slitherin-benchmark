pragma solidity ^0.8.14;

import "./ReentrancyGuard.sol";
import "./ERC721.sol";
import "./IERC721Receiver.sol";

import "./IDarwinStaking.sol";
import "./IERC20.sol";
import "./IMultiplierNFT.sol";
import "./IMultiplierNFT.sol";

contract DarwinStaking is IDarwinStaking, ReentrancyGuard, IERC721Receiver {
    IERC20 public darwin;
    IERC20 public stakedDarwin;
    address public dev;

    uint public constant BASE_APR = 5e18; // 5%
    uint public constant LOCK_BONUS_APR = 2e18; // 2% more if locked for 1 year
    uint private constant _SECONDS_IN_YEAR = 31_536_000;

    mapping(address => bool) public supportedNFT;
    mapping(address => UserInfo) public userInfo;

    constructor(address _darwin, address _stakedDarwin, address[] memory _supportedNFTs) {
        dev = msg.sender;
        darwin = IERC20(_darwin);
        stakedDarwin = IERC20(_stakedDarwin);
        for (uint i = 0; i < _supportedNFTs.length; i++) {
            supportedNFT[_supportedNFTs[i]] = true;
        }
    }

    function stake(uint _amount, uint _lockPeriod) external nonReentrant {
        require(darwin.transferFrom(msg.sender, address(this), _amount), "DarwinStaking: STAKE_FAILED");

        _claim();
        if (userInfo[msg.sender].lockEnd <= block.timestamp) {
            userInfo[msg.sender].lockStart = block.timestamp;
            userInfo[msg.sender].lockEnd = block.timestamp + _lockPeriod;
        } else {
            userInfo[msg.sender].lockEnd += _lockPeriod;
        }

        stakedDarwin.mint(msg.sender, _amount);

        emit Stake(msg.sender, _amount);
    }

    function withdraw(uint _amount) public nonReentrant {
        uint claimAmount = _claim();
        if (_amount > 0) {
            require(userInfo[msg.sender].lockEnd <= block.timestamp, "DarwinStaking: LOCKED");
            require(_amount <= stakedDarwin.balanceOf(msg.sender), "DarwinStaking: NOT_ENOUGH_sDARWIN");
            stakedDarwin.burn(msg.sender, _amount);
            require(darwin.transfer(msg.sender, _amount), "DarwinStaking: WITHDRAW_TRANSFER_FAILED");
        }
        emit Withdraw(msg.sender, _amount, claimAmount);
    }

    function _claim() internal returns (uint claimAmount) {
        claimAmount = claimableDarwin(msg.sender);
        userInfo[msg.sender].lastClaimTimestamp = block.timestamp;
        if (claimAmount > 0) {
            darwin.mint(msg.sender, claimAmount);
        }
    }

    function bonusAPR(address _user) public view returns(uint256 bonus) {
        uint lockPeriod = userInfo[_user].lockEnd - userInfo[_user].lockStart;
        if (lockPeriod >= _SECONDS_IN_YEAR) {
            return LOCK_BONUS_APR;
        } else {
            return (lockPeriod * LOCK_BONUS_APR) / _SECONDS_IN_YEAR;
        }
    }

    function claimableDarwin(address _user) public view returns(uint256 claimable) {
        uint staked = stakedDarwin.balanceOf(_user);
        if (staked == 0) {
            return 0;
        }
        uint claim = userInfo[_user].lastClaimTimestamp;
        uint lockEnd = userInfo[_user].lockEnd;
        uint boost = userInfo[_user].boost;
        uint timePassedFromLastClaim = (block.timestamp - claim);

        // lock bonus calculations
        uint bonusClaimable;
        if (claim < lockEnd) {
            uint timePassedUntilLockEndOrNow = ((lockEnd > block.timestamp ? block.timestamp : lockEnd) - claim);
            bonusClaimable = (staked * bonusAPR(_user) * timePassedUntilLockEndOrNow) / (100e18 * _SECONDS_IN_YEAR);
        }

        claimable = (staked * BASE_APR * timePassedFromLastClaim) / (100e18 * _SECONDS_IN_YEAR) + bonusClaimable;
        
        if (boost > 0) {
            claimable += ((claimable * boost) / 1000);
        }
    }

    function stakeEvoture(address _nft, uint _tokenId) external nonReentrant {
        require(userInfo[msg.sender].nft == address(0), "DarwinStaking: NFT_ALREADY_STAKED");
        require(supportedNFT[_nft], "DarwinStaking: UNSUPPORTED_NFT");

        _claim();
        IERC721(_nft).safeTransferFrom(msg.sender, address(this), _tokenId);
        userInfo[msg.sender].nft = _nft;
        userInfo[msg.sender].boost = IMultiplierNFT(_nft).multipliers(_tokenId);
        userInfo[msg.sender].tokenId = _tokenId;

        emit StakeEvoture(msg.sender, _tokenId, userInfo[msg.sender].boost);
    }

    function withdrawEvoture() external nonReentrant {
        require(userInfo[msg.sender].nft != address(0), "DarwinStaking: NO_NFT_TO_WITHDRAW");

        _claim();
        IERC721(userInfo[msg.sender].nft).safeTransferFrom(address(this), msg.sender, userInfo[msg.sender].tokenId);
        userInfo[msg.sender].nft = address(0);
        userInfo[msg.sender].boost = 0;
        userInfo[msg.sender].tokenId = 0;

        emit WithdrawEvoture(msg.sender, userInfo[msg.sender].tokenId);
    }

    function addSupportedNFT(address _nft) external {
        require(msg.sender == dev, "DarwinStaking: CALLER_IS_NOT_DEV");
        supportedNFT[_nft] = true;
    }

    function removeSupportedNFT(address _nft) external {
        require(msg.sender == dev, "DarwinStaking: CALLER_IS_NOT_DEV");
        supportedNFT[_nft] = false;
    }

    function getUserInfo(address _user) external view returns (UserInfo memory) {
        return userInfo[_user];
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
}
