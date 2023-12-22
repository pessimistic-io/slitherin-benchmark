//SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "./IERC20.sol";
import "./ISled.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";
import "./AggregatorPriceFeeds.sol";
import "./IERC20Metadata.sol";
import "./BancorFormula.sol";
import "./ITreasury.sol";
import "./ReentrancyGuard.sol";
import "./Pausable.sol";
import "./Ownable.sol";

/**
 * @title ArbiSled Treasury
 * @author Mugen Dev, modified by ArbiSled Dev
 * @notice Minimal implementation of Bancors Power.sol
 * to allow users to deposit and exchange whitelisted ERC20 at usd value for
 * ArbiSled ERC20 tokens.
 */

contract Treasury is
    BancorFormula,
    ITreasury,
    Ownable,
    ReentrancyGuard,
    Pausable
{
    using SafeERC20 for IERC20;

    /*///////////////////////////////////////////////////////////////
                                 CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint256 public constant SCALE = 10 ** 18;
    uint256 internal constant VALID_PERIOD = 1 days;
    uint256 internal constant MIN_VALUE = 50 * 10 ** 18;
    uint256 public constant RESERVE_RATIO = 800000;
    uint256[] public boosts = [
        142,
        139,
        136,
        133,
        130,
        127,
        124,
        121,
        118,
        115,
        112,
        109,
        106,
        103
    ];

    /*///////////////////////////////////////////////////////////////
                                IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    ISled public immutable sled;

    /*///////////////////////////////////////////////////////////////
                                 State Variables
    //////////////////////////////////////////////////////////////*/

    address public administrator;
    address public Communicator;
    address public strategyHub;
    uint256 public reserveBalance = 10 * SCALE;
    uint256 public valueDeposited;
    uint256 public s_totalSupply;
    address public teamFund;
    uint256 public depositCap;
    uint256 public launchTime = 0;
    bool public adminRemoved = false;
    uint256 public depositFees = 100; // 10 %

    enum WorkflowStatus {
        Closed,
        FirstRound,
        SecondRound,
        ThirdRound,
        Public
    }
    WorkflowStatus public workflow;

    /*///////////////////////////////////////////////////////////////
                                 Mappings
    //////////////////////////////////////////////////////////////*/

    ///@notice listed of whitelisted ERC20s that can be deposited
    mapping(IERC20 => bool) public depositableTokens;

    ///@notice token address point to their associated price feeds.
    mapping(IERC20 => AggregatorPriceFeeds) public priceFeeds;

    mapping(address => bool) public isInFirstRound;
    mapping(address => bool) public isInSecondRound;
    mapping(address => bool) public isInThirdRound;

    /*///////////////////////////////////////////////////////////////
                                 Custom Errors
    //////////////////////////////////////////////////////////////*/

    error NotDepositable();
    error NotUpdated();
    error InvalidPrice();
    error NotOwner();
    error NotCommunicator();
    error UnderMinDeposit();
    error CapReached();
    error AdminRemoved();

    /**
     * @param _sled Sled ERC20 address
     * @param _strategyHub The strategy hub address that controls deposited funds
     * @param _administrator address with high level access controls
     * @notice administrator is kept initially for efficency in the early stages
     * but can be removed through governance at anytime.
     */
    constructor(
        address _sled,
        address _strategyHub,
        address _administrator,
        address _teamFund
    ) {
        sled = ISled(_sled);
        strategyHub = _strategyHub;
        s_totalSupply += 1e18;
        administrator = _administrator;
        teamFund = _teamFund;
    }

    /*///////////////////////////////////////////////////////////////
                                 User Functions
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev allows for users to deposit whitelisted assets and calculates their USD value for the bonding curve
     * given that the cap is not reached yet.
     * @param _token the token which is to be deposited
     * @param _amount the amount for this particular deposit
     * @notice uses s_totalSupply rather than totalsupply() in order to prevent
     * accounting issues once launched on multiple chains. As the strategy hub will serve as
     * the global truth for pricing in the mint function.
     */

    function deposit(
        IERC20Metadata _token,
        uint256 _amount
    ) external nonReentrant depositable(_token) Capped whenNotPaused {
        require(isAllowed(msg.sender), "Not allowed");
        require(launchTime > 0, "Not launched yet");
        require(_amount > 0, "Deposit must be more than 0");
        uint8 decimals = IERC20Metadata(_token).decimals();
        (uint256 tokenPrice, AggregatorPriceFeeds tokenFeed) = getPrice(_token);
        uint256 value;
        if (decimals != 18) {
            value =
                (tokenPrice * _amount * 1e18) /
                10 ** (decimals + tokenFeed.decimals());
        } else {
            value = (tokenPrice * _amount) / 10 ** (tokenFeed.decimals());
        }
        require(value >= MIN_VALUE, "less than min deposit");
        uint256 calculated = _continuousMint(value);
        s_totalSupply += calculated;
        valueDeposited += value;
        emit Deposit(msg.sender, _token, value);
        IERC20(_token).safeTransferFrom(msg.sender, strategyHub, _amount);
        if (depositFees > 0) {
            uint256 fees = (calculated * depositFees) / 10000;
            sled.mint(teamFund, fees);
        }
        sled.mint(msg.sender, calculated);
    }

    /*///////////////////////////////////////////////////////////////
                            Cross Chain Functions
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice receives information from the Communicator and
     * relays it back to be sent to other chains.
     * @param _amount value of the deposit on the specific chain
     */

    function receiveMessage(
        uint256 _amount
    ) external override returns (uint256) {
        if (msg.sender != Communicator) {
            revert NotCommunicator();
        }
        uint256 test = _continuousMint(_amount);
        s_totalSupply += test;
        return test;
    }

    /*///////////////////////////////////////////////////////////////
                                 Admin Functions
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice adds token to whitelisted assets with its associated oracle
     * @param _token address of the token
     * @param _pricefeed address for the pricefeed
     * @dev onlyOwnerOrAdmin allows for the administrator or the owner to call this function
     */

    function addTokenInfo(
        IERC20 _token,
        address _pricefeed
    ) external onlyOwnerOrAdmin {
        priceFeeds[_token] = AggregatorPriceFeeds(_pricefeed);
        depositableTokens[_token] = true;
        emit DepositableToken(_token, _pricefeed);
    }

    function setWorkFlow(uint256 _workflow) external onlyOwnerOrAdmin {
        workflow = WorkflowStatus(_workflow);
    }

    function whiteListUser(
        address _user,
        uint256 round,
        bool whitelisted
    ) internal onlyOwnerOrAdmin {
        if (round == 1) {
            isInFirstRound[_user] = whitelisted;
        } else if (round == 2) {
            isInSecondRound[_user] = whitelisted;
        } else if (round == 3) {
            isInThirdRound[_user] = whitelisted;
        }
    }

    function whiteListUsers(
        address[] memory addresses,
        uint256 round,
        bool whitelisted
    ) external onlyOwnerOrAdmin {
        for (uint256 i = 0; i < addresses.length; i++) {
            whiteListUser(addresses[i], round, whitelisted);
        }
    }

    /**
     * @notice Removes the token from the list of
     * whitelisted assets and its associated oracle
     * @param _token address of the token
     */
    function removeTokenInfo(IERC20 _token) external onlyOwnerOrAdmin {
        delete depositableTokens[_token];
        delete priceFeeds[_token];
        emit TokenRemoved(_token);
    }

    ///@param _comms address of the communicator contract
    function setCommunicator(address _comms) external onlyOwnerOrAdmin {
        Communicator = _comms;
    }

    /**
     * @notice setting the cap for inital deposits while code is fresh
     * @param _amount what the Cap is set to
     * @dev the cap will be evaluated in USD from the valueDeposited variable
     * so 100 * 1e18 will set the cap to 100 USD
     */
    function setCap(uint256 _amount) external onlyOwnerOrAdmin {
        depositCap = _amount;
    }

    /**
     * @notice setting the deposit fees
     * @param _fees 10% = 100
     */
    function setDepositFees(uint256 _fees) external onlyOwnerOrAdmin {
        depositFees = _fees;
    }

    /**
     * @notice sets the new administrtor if they have not already been removed
     * @param newAdmin the address of the new Administrator
     */
    function setAdministrator(address newAdmin) external onlyOwnerOrAdmin {
        if (adminRemoved != false) {
            revert AdminRemoved();
        }

        administrator = newAdmin;
    }

    /**
     * @notice removes the admin and set it to the zero address
     * @dev once removed a new admin cannot be set
     */
    function removeAdmin() external onlyOwner {
        administrator = address(0);
        adminRemoved = true;
    }

    /**
     * @notice change the team fund receiving fees
     * @param _teamFund the address of the new team fund
     */
    function setTeamFund(address _teamFund) external onlyOwnerOrAdmin {
        teamFund = _teamFund;
    }

    ///@notice inherited from pausable, and pauses deposits
    function pauseDeposits() external onlyOwnerOrAdmin {
        _pause();
    }

    function launch() external onlyOwnerOrAdmin {
        require(launchTime == 0, "Already launched");
        launchTime = block.timestamp;
    }

    ///@notice inherited from pausable, and unpauses deposits
    function unpauseDeposits() external onlyOwnerOrAdmin {
        _unpause();
    }

    function changeTreasury(address _strategyHub) external onlyOwnerOrAdmin {
        strategyHub = _strategyHub;
    }

    /*///////////////////////////////////////////////////////////////
                            View Functions
    //////////////////////////////////////////////////////////////*/

    function getPrice(
        IERC20 _token
    ) internal view returns (uint256, AggregatorPriceFeeds) {
        AggregatorPriceFeeds feed = priceFeeds[_token];
        (, int256 price, , uint256 updatedAt, ) = feed.latestRoundData();
        if (block.timestamp - updatedAt > VALID_PERIOD) {
            revert NotUpdated();
        }
        if (price <= 0) {
            revert InvalidPrice();
        }
        return (uint256(price), feed);
    }

    function readSupply() external view returns (uint256) {
        return s_totalSupply;
    }

    function checkDepositable(IERC20 _token) external view returns (bool) {
        return depositableTokens[_token];
    }

    ///@notice returns the current USD price to mint 1 Sled Token
    function pricePerToken() external view returns (uint256) {
        uint256 _price = (100 * 1e18) / calculateContinuousMintReturn(1e18);
        return _price;
    }

    /*///////////////////////////////////////////////////////////////
                        Modifier Functions 
    //////////////////////////////////////////////////////////////*/

    modifier depositable(IERC20 _token) {
        if (depositableTokens[_token] != true) {
            revert NotDepositable();
        }
        _;
    }

    modifier Capped() {
        _;
        if (depositCap < valueDeposited) {
            revert CapReached();
        }
    }

    modifier onlyOwnerOrAdmin() {
        require(
            msg.sender == owner() || msg.sender == administrator,
            "Not Owner"
        );
        _;
    }

    /*///////////////////////////////////////////////////////////////
                        Bonding Curve Logic
    //////////////////////////////////////////////////////////////*/

    function calculateContinuousMintReturn(
        uint256 _amount
    ) public view returns (uint256 mintAmount) {
        uint256 amount = purchaseTargetAmount(
            s_totalSupply,
            reserveBalance,
            uint32(RESERVE_RATIO),
            _amount
        );
        uint256 ignitionBoost = calculateIgnitionBoost();
        if (ignitionBoost > 100) amount = (amount * ignitionBoost) / 100;
        return amount;
    }

    function calculateIgnitionBoost() public view returns (uint256 boost) {
        uint256 daysSinceLaunch = (block.timestamp - launchTime) / 1 days;
        if (daysSinceLaunch >= boosts.length) return 100;
        return boosts[daysSinceLaunch];
    }

    function _continuousMint(uint256 _deposit) internal returns (uint256) {
        uint256 amount = calculateContinuousMintReturn(_deposit);
        reserveBalance += _deposit;
        return amount;
    }

    function isAllowed(address _user) public view returns (bool) {
        if (workflow == WorkflowStatus.FirstRound) {
            return isInFirstRound[_user];
        } else if (workflow == WorkflowStatus.SecondRound) {
            return isInSecondRound[_user];
        } else if (workflow == WorkflowStatus.ThirdRound) {
            return isInThirdRound[_user];
        } else if (workflow == WorkflowStatus.Closed) {
            return false;
        }
        return true;
    }

    receive() external payable {}
}

