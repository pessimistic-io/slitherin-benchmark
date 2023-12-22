// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import "./Initializable.sol";
import "./AccessControlUpgradeable.sol";
import "./UUPSUpgradeable.sol";
import "./IERC20.sol";
import "./IERC20Metadata.sol";
import "./IERC721Receiver.sol";


contract Staker is Initializable, AccessControlUpgradeable, UUPSUpgradeable {

    bytes32 public constant PORTFOLIO_AGENT_ROLE = keccak256("PORTFOLIO_AGENT_ROLE");
    bytes32 public constant UNIT_ROLE = keccak256("UNIT_ROLE");

    // Addresses used
    IVoter public voter;
    IVe public veToken;
    IVeClaim public vetClaim;
    uint256 public veTokenId;
    IERC20 public want;

    address public rewardWallet;

    // Strategy mapping
    mapping(address => address) public whitelistedStrategy;

    event CreateLock(address indexed user, uint256 veTokenId, uint256 amount, uint256 unlockTime);
    event IncreaseTime(address indexed user, uint256 veTokenId, uint256 unlockTime);
    event ClaimVeEmissions(address indexed user, uint256 veTokenId, uint256 amount);
    event ClaimRewards(address indexed user, address gauges, address[] tokens);
    event TransferVeToken(address indexed user, address to, uint256 veTokenId);
    event ClaimBribe(address token, uint256 amount);


    // ---  modifiers

    modifier onlyAdmin() {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Restricted to admins");
        _;
    }

    modifier onlyPortfolioAgent() {
        require(hasRole(PORTFOLIO_AGENT_ROLE, msg.sender), "Restricted to Portfolio Agent");
        _;
    }

    // Checks that caller is the strategy assigned to a specific gauge.
    modifier onlyWhitelist(address _gauge) {
        require(whitelistedStrategy[_gauge] == msg.sender, "!whitelisted");
        _;
    }


    // ---  constructor

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {}

    function initialize() initializer public {
        __AccessControl_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PORTFOLIO_AGENT_ROLE, msg.sender);

    }

    function _authorizeUpgrade(address newImplementation)
    internal
    onlyRole(DEFAULT_ADMIN_ROLE)
    override
    {}


    struct SetupParams {
        address voter;
        address veToken;
        address vetClaim;
        uint256 veTokenId;
        address rewardWallet;
    }


    function setParams(SetupParams calldata params) external onlyAdmin {
        voter = IVoter(params.voter);
        veToken = IVe(params.veToken);
        vetClaim = IVeClaim(params.vetClaim);
        veTokenId = params.veTokenId;
        want = IERC20(veToken.token());
        rewardWallet = params.rewardWallet;

        want.approve(address(veToken), type(uint).max);
    }



    //  --- Pass Through Contract Functions Below ---

    // Pass through a deposit to a boosted gauge
    function deposit(address _gauge, uint256 _amount, address _token) external onlyWhitelist(_gauge) {
        // Grab needed info
        IERC20 _underlying = IERC20(_token);
        // Take before balances snapshot and transfer want from strat
        _underlying.transferFrom(msg.sender, address(this), _amount);
        IGauge(_gauge).deposit(_amount, veTokenId);
    }

    // Pass through a withdrawal from boosted chef
    function withdraw(address _gauge, uint256 _amount, address _token) external onlyWhitelist(_gauge) {
        // Grab needed pool info
        IERC20 _underlying = IERC20(_token);
        uint256 _before = IERC20(_underlying).balanceOf(address(this));
        IGauge(_gauge).withdraw(_amount);
        uint256 _balance = _underlying.balanceOf(address(this)) - _before;
        _underlying.transfer(msg.sender, _balance);
    }

    // Get Rewards and send to strat
    function harvestRewards(address _gauge, address[] calldata tokens) external onlyWhitelist(_gauge) {
        IGauge(_gauge).getReward(address(this), tokens);
        for (uint i; i < tokens.length;) {
            IERC20(tokens[i]).transfer(msg.sender, IERC20(tokens[i]).balanceOf(address(this)));
        unchecked {++i;}
        }
    }

    /**
     * @dev Whitelists a strategy address to interact with the Boosted Chef and gives approvals.
     * @param _strategy new strategy address.
     */
    function whitelistStrategy(address _strategy, address _token, address _gauge) external onlyPortfolioAgent {
        IERC20 _want = IERC20(_token);
        uint256 stratBal = IGauge(_gauge).balanceOf(address(this));
        require(stratBal == 0, "!inactive");

        _want.approve(_gauge, 0);
        _want.approve(_gauge, type(uint256).max);
        whitelistedStrategy[_gauge] = _strategy;
    }

    /**
     * @dev Removes a strategy address from the whitelist and remove approvals.
     */
    function blacklistStrategy(address _token, address _gauge) external onlyPortfolioAgent {
        IERC20 _want = IERC20(_token);
        _want.approve(_gauge, 0);
        whitelistedStrategy[_gauge] = address(0);
    }


    // --- Vote Related Functions ---

    // claim veToken emissions and increases locked amount in veToken
    function claimVeEmissions() public {
        uint256 _amount = vetClaim.claim(veTokenId);
        emit ClaimVeEmissions(msg.sender, veTokenId, _amount);
    }

    // vote for emission weights
    function vote(address[] calldata _tokenVote, int256[] calldata _weights) external onlyPortfolioAgent {
        claimVeEmissions();
        voter.vote(veTokenId, _tokenVote, _weights);
    }

    function claimBribes(address[] calldata _bribes, address[][] calldata _tokens) external onlyPortfolioAgent {
        require(rewardWallet != address(0), 'rewardWallet is zero');

        voter.claimBribes(_bribes, _tokens, veTokenId);
    }

    function transferBribes(address[] calldata _tokens) external onlyPortfolioAgent{
        for (uint256 i = 0; i < _tokens.length; i++) {

            IERC20 token = IERC20(_tokens[i]);
            uint256 amount = token.balanceOf(address(this));
            if(amount > 0){
                token.transfer(rewardWallet, amount);
                emit ClaimBribe(address(token), amount);
            }
        }
    }

    // reset current votes
    function resetVote() external onlyPortfolioAgent {
        voter.reset(veTokenId);
    }


    // whitelist new token
    function whitelist(address _token) external onlyPortfolioAgent {
        voter.whitelist(_token, veTokenId);
    }


    // --- Token Management ---

    // create a new veToken if none is assigned to this address
    function createLock(uint256 _amount, uint256 _lock_duration, bool init) external onlyPortfolioAgent {
        require(veTokenId == 0, "veToken > 0");

        if (init) {
            veTokenId = veToken.tokenOfOwnerByIndex(msg.sender, 0);
            veToken.transferFrom(msg.sender, address(this), veTokenId);
        } else {
            require(_amount > 0, "amount == 0");
            want.transferFrom(address(msg.sender), address(this), _amount);
            veTokenId = veToken.createLock(_amount, _lock_duration);

            emit CreateLock(msg.sender, veTokenId, _amount, _lock_duration);
        }
    }

    // merge voting power of two veTokens by burning the _from veToken, _from must be detached and not voted with
    function merge(uint256 _fromId) external {
        require(_fromId != veTokenId, "cannot burn main veTokenId");
        veToken.transferFrom(msg.sender, address(this), _fromId);
        veToken.merge(_fromId, veTokenId);
    }

    // extend lock time for veToken to increase voting power
    function increaseUnlockTime(uint256 _lock_duration) external onlyPortfolioAgent {
        veToken.increaseUnlockTime(veTokenId, _lock_duration);
        emit IncreaseTime(msg.sender, veTokenId, _lock_duration);
    }

    // transfer veToken to another address, must be detached from all gauges first
    function transferVeToken(address _to) external onlyAdmin {
        uint256 transferId = veTokenId;
        veTokenId = 0;
        veToken.transferFrom(address(this), _to, transferId);


        emit TransferVeToken(msg.sender, _to, transferId);
    }

    // confirmation required for receiving veToken to smart contract
    function onERC721Received(
        address operator,
        address from,
        uint tokenId,
        bytes calldata data
    ) external view returns (bytes4) {
        operator;
        from;
        tokenId;
        data;
        require(msg.sender == address(veToken), "!veToken");
        return bytes4(keccak256("onERC721Received(address,address,uint,bytes)"));
    }
}


interface IVeClaim {
    function claim(uint256 tokenId) external returns (uint);
}

interface IVoter {
    function vote(uint tokenId, address[] calldata _poolVote, int256[] calldata _weights) external;

    function whitelist(address token, uint256 tokenId) external;

    function gauges(address lp) external view returns (address);

    function ve() external view returns (address);

    function minter() external view returns (address);

    function reset(uint256 _id) external;

    function bribes(address _lp) external view returns (address);

    function internal_bribes(address _lp) external view returns (address);

    function claimBribes(address[] memory _bribes, address[][] memory _tokens, uint _tokenId) external;
}

interface IVe {
    function createLock(uint256 _value, uint256 _lockDuration) external returns (uint256 _tokenId);

    function increaseAmount(uint256 tokenId, uint256 value) external;

    function increaseUnlockTime(uint256 tokenId, uint256 duration) external;

    function withdraw(uint256 tokenId) external;

    function balanceOfNFT(uint256 tokenId) external view returns (uint256 balance);

    function locked(uint256 tokenId) external view returns (uint256 amount, uint256 endTime);

    function token() external view returns (address);

    function transferFrom(address from, address to, uint256 id) external;

    function tokenOfOwnerByIndex(address user, uint index) external view returns (uint);

    function merge(uint256 from, uint256 to) external;
}

interface IGauge {
    function getReward(address user, address[] calldata tokens) external;

    function getReward(uint256 id, address[] calldata tokens) external;

    function deposit(uint amount, uint tokenId) external;

    function withdraw(uint amount) external;

    function balanceOf(address user) external view returns (uint);
}

