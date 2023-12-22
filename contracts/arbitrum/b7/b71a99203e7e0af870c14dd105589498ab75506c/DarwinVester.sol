// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./IERC20.sol";
import "./IERC721Receiver.sol";
import "./IERC721.sol";

import {IDarwinVester} from "./IDarwinVester.sol";
import {IDarwin} from "./IDarwin.sol";
import {IEvoturesNFT} from "./IEvoturesNFT.sol";

/// @title Darwin Vester
contract DarwinVester is IDarwinVester, ReentrancyGuard, Ownable, IERC721Receiver {

    /// @notice Percentage of monthly interest (0.625%, 7.5% in a year)
    uint256 public constant INTEREST = 625;
    /// @notice Number of months thru which vested darwin will be fully withdrawable
    uint256 public constant MONTHS = 12;
    /// @notice Above in seconds
    uint256 public constant VESTING_TIME = MONTHS * (30 days);

    mapping(address => UserInfo) public userInfo;
    address[] users;
    uint[] atLaunch;

    /// @notice The Darwin token
    IERC20 public darwin;
    /// @notice Vest user address
    address public deployer;
    mapping(address => bool) public supportedNFT;

    bool private _isInitialized;

    modifier onlyInitialized() {
        if (!_isInitialized) {
            revert NotInitialized();
        }
        _;
    }

    modifier onlyVestUser() {
        if (userInfo[msg.sender].vested > 0) {
            revert NotVestUser();
        }
        _;
    }

    constructor(address[] memory _users, uint[] memory _atLaunch, uint[] memory _due, address[] memory _supportedNFTs) {
        require(_users.length == _due.length && _due.length == _atLaunch.length, "Vester: Invalid _userInfo");
        for (uint i = 0; i < _users.length; i++) {
            userInfo[_users[i]].vested = _due[i] - _atLaunch[i];
        }
        users = _users;
        atLaunch = _atLaunch;
        deployer = msg.sender;
        for (uint i = 0; i < _supportedNFTs.length; i++) {
            supportedNFT[_supportedNFTs[i]] = true;
        }
    }

    function init(address _darwin) external {
        require (msg.sender == deployer, "Vester: Caller not Deployer");
        require (address(darwin) == address(0), "Vester: Darwin already set");
        darwin = IERC20(_darwin);
    }

    function startVesting() external {
        require(!_isInitialized, "Vester: Already initialized");
        _isInitialized = true;
        for (uint i = 0; i < users.length; i++) {
            emit Vest(users[i], userInfo[users[i]].vested);

            userInfo[users[i]].claimed = 0;
            userInfo[users[i]].withdrawn = 0;
            userInfo[users[i]].vestTimestamp = block.timestamp;
            IERC20(address(darwin)).transfer(users[i], atLaunch[i]);
        }
    }

    // Withdraws darwin from contract and also claims any minted darwin. If _amount == 0, does not withdraw but just claim.
    function withdraw(uint _amount) external onlyInitialized onlyVestUser nonReentrant {
        _withdraw(msg.sender, _amount);
    }

    function _withdraw(address _user, uint _amount) internal {
        _claim(_user);
        if (_amount > 0) {
            uint withdrawable = withdrawableDarwin(_user);
            if (_amount > withdrawable) {
                revert AmountExceedsWithdrawable();
            }
            userInfo[_user].vested -= _amount;
            userInfo[_user].withdrawn += _amount;
            if (!darwin.transfer(_user, _amount)) {
                revert TransferFailed();
            }
            emit Withdraw(_user, _amount);
        }
    }

    function _claim(address _user) internal {
        uint claimAmount = claimableDarwin(msg.sender);
        if (claimAmount > 0) {
            userInfo[_user].claimed += claimAmount;
            IDarwin(address(darwin)).mint(_user, claimAmount);
            emit Claim(_user, claimAmount);
        }
    }

    function stakeEvoture(address _nft, uint16 _tokenId) external nonReentrant {
        require(userInfo[msg.sender].nft == address(0), "DarwinVester: NFT_ALREADY_STAKED");
        require(supportedNFT[_nft], "DarwinVester: UNSUPPORTED_NFT");

        _claim(msg.sender);
        IERC721(_nft).safeTransferFrom(msg.sender, address(this), _tokenId);
        userInfo[msg.sender].nft = _nft;
        userInfo[msg.sender].boost = IEvoturesNFT(_nft).multipliers(_tokenId);
        userInfo[msg.sender].tokenId = _tokenId;

        emit StakeEvoture(msg.sender, _tokenId, userInfo[msg.sender].boost);
    }

    function withdrawEvoture() external nonReentrant {
        require(userInfo[msg.sender].nft != address(0), "DarwinVester: NO_NFT_TO_WITHDRAW");

        _claim(msg.sender);
        IERC721(userInfo[msg.sender].nft).safeTransferFrom(address(this), msg.sender, userInfo[msg.sender].tokenId);
        userInfo[msg.sender].nft = address(0);
        userInfo[msg.sender].boost = 0;
        userInfo[msg.sender].tokenId = 0;

        emit WithdrawEvoture(msg.sender, userInfo[msg.sender].tokenId);
    }

    function addSupportedNFT(address _nft) external {
        require(msg.sender == deployer, "DarwinVester: CALLER_IS_NOT_DEV");
        supportedNFT[_nft] = true;
    }

    function removeSupportedNFT(address _nft) external {
        require(msg.sender == deployer, "DarwinVester: CALLER_IS_NOT_DEV");
        supportedNFT[_nft] = false;
    }

    function withdrawableDarwin(address _user) public view returns(uint256 withdrawable) {
        uint vested = userInfo[_user].vested;
        if (vested == 0) {
            return 0;
        }
        uint withdrawn = userInfo[_user].withdrawn;
        uint start = userInfo[_user].vestTimestamp;
        uint passedMonthsFromStart = (block.timestamp - start) / (30 days);
        if (passedMonthsFromStart > MONTHS) {
            passedMonthsFromStart = MONTHS;
        }
        withdrawable = (((vested + withdrawn) * passedMonthsFromStart) / MONTHS) - withdrawn;
        if (withdrawable > vested) {
            withdrawable = vested;
        }
    }

    function claimableDarwin(address _user) public view returns(uint256 claimable) {
        uint vested = userInfo[_user].vested;
        if (vested == 0) {
            return 0;
        }
        uint claimed = userInfo[_user].claimed;
        uint boost = userInfo[_user].boost;
        uint start = userInfo[_user].vestTimestamp;
        uint passedMonthsFromStart = (block.timestamp - start) / (30 days);
        claimable = (((vested * INTEREST) / 100000) * passedMonthsFromStart) - claimed;

        if (boost > 0) {
            claimable += ((claimable * boost) / 1000);
        }
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

