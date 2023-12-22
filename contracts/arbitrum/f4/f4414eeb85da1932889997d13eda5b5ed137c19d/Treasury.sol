// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.7.5;

import "./SafeMath.sol";
import "./SafeERC20.sol";

import "./IERC20.sol";
import "./IERC20Metadata.sol";
import "./IPana.sol";
import "./IsPana.sol";
import "./IBondingCalculator.sol";
import "./ITreasury.sol";
import "./ISupplyContoller.sol";

import "./PanaAccessControlled.sol";

contract PanaTreasury is PanaAccessControlled, ITreasury {
    /* ========== DEPENDENCIES ========== */

    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    /* ========== EVENTS ========== */

    event Deposit(address indexed token, uint256 amount, uint256 payout);
    event DepositForRedemption(address indexed token, uint256 amount, uint256 send);
    event Managed(address indexed token, uint256 amount);
    event Minted(address indexed caller, address indexed recipient, uint256 amount);
    event PermissionQueued(STATUS indexed status, address queued);
    event Permissioned(address addr, STATUS indexed status, bool result);
    event MintedForNFTTreasury(uint256 amount, address treasury);

    /* ========== DATA STRUCTURES ========== */

    enum STATUS {
        RESERVEDEPOSITOR,
        RESERVETOKEN,
        RESERVEMANAGER,
        LIQUIDITYDEPOSITOR,
        LIQUIDITYTOKEN,
        LIQUIDITYMANAGER,
        REWARDMANAGER,
        SPANA,
        PANAREDEEMER,
        NFTTREASURY
    }

    struct Queue {
        STATUS managing;
        address toPermit;
        address supplyController;
        uint256 timelockEnd;
        bool nullify;
        bool executed;
    }

    /* ========== STATE VARIABLES ========== */

    IPana public immutable PANA;
    IsPana public sPANA;

    mapping(STATUS => address[]) public registry;
    mapping(STATUS => mapping(address => bool)) public permissions;
    mapping(address => address) public supplyController;

    Queue[] public permissionQueue;
    uint256 public immutable blocksNeededForQueue;

    bool public timelockEnabled;
    bool public initialized;

    uint256 public onChainGovernanceTimelock;

    // Percentage of PANA balance available for redemption.
    // Percentage specified to 4 precision digits. 100 = 1% = 0.01
    uint256 public redemptionLimit;

    string internal notAccepted = "Treasury: not accepted";
    string internal notApproved = "Treasury: not approved";
    string internal invalidToken = "Treasury: invalid token";
    string internal noValuation = "Treasury: asset is not a reserve token";

    /* ========== CONSTRUCTOR ========== */

    constructor(
        address _pana,
        uint256 _timelock,
        address _authority
    ) PanaAccessControlled(IPanaAuthority(_authority)) {
        require(_pana != address(0), "Zero address: PANA");
        PANA = IPana(_pana);

        timelockEnabled = false;
        initialized = false;
        blocksNeededForQueue = _timelock;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /**
     * @notice allow approved address to deposit an asset for PANA
     * @param _amount uint256
     * @param _token address
     * @param _payout uint256
     * @return send_ uint256
     */
    function deposit(
        uint256 _amount,
        address _token,
        uint256 _payout
    ) external override returns (uint256) {
        if (permissions[STATUS.RESERVETOKEN][_token]) {
            require(permissions[STATUS.RESERVEDEPOSITOR][msg.sender], notApproved);
        } else if (permissions[STATUS.LIQUIDITYTOKEN][_token]) {
            require(permissions[STATUS.LIQUIDITYDEPOSITOR][msg.sender], notApproved);
        } else {
            revert(invalidToken);
        }

        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
        PANA.mint(msg.sender, _payout);

        emit Deposit(_token, _amount, _payout);

        if(permissions[STATUS.LIQUIDITYTOKEN][_token] 
            && supplyController[_token] != address(0)
            && ISupplyContoller(supplyController[_token]).supplyControlEnabled()
            && ISupplyContoller(supplyController[_token]).paramsSet()) {
                _updateSupplyRatio(_token);
        }

        return _payout;
    }

    /**
     * @notice allow approved address to deposit reserve token for available PANA. No new PANA is minted.
     * @param _amount uint256
     * @param _token address
     * @return send_ uint256
     */
    function depositForRedemption(uint _amount, address _token) external override returns (uint256 send_) {
        require(permissions[STATUS.RESERVETOKEN][_token], notAccepted);
        require(permissions[STATUS.PANAREDEEMER][msg.sender], notApproved);

        // redemption is always calculated as 1:100
        send_ = tokenValue(_token, _amount);
        require(send_ <= availableForRedemption(), "Not enough PANA reserves");
       
        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
        IERC20(PANA).safeTransfer(msg.sender, send_);

        emit DepositForRedemption(_token, _amount, send_);
    }

    /**
     * @notice  executes loss ratio management
     * @dev     this function is for internal usage, it expects all required checks to be performed before a call
     * @param   _lpToken a target liquidity token
     */
    function _updateSupplyRatio(address _lpToken) internal {
        ISupplyContoller controller = ISupplyContoller(supplyController[_lpToken]);

        (uint256 pana, uint256 slp, bool burn) = controller.getSupplyControlAmount();
        if (pana > 0) {
            if (burn) {
                // send LP tokens to supplyController and burn liquidity
                uint256 toBurn = IERC20(_lpToken).balanceOf(address(this));
                if (toBurn > slp) {
                    toBurn = slp;
                }

                IERC20(_lpToken).safeTransfer(address(controller), toBurn);
                controller.burn(toBurn);
            } else {
                // send PANA to supplyController and add liquidity
                uint256 toAdd = IERC20(PANA).balanceOf(address(this));
                if (toAdd > pana) {
                    toAdd = pana;
                }

                IERC20(PANA).safeTransfer(address(controller), toAdd);
                controller.add(toAdd);
            }
        }
    }

    /**
     * @notice  externally called version of _updateSupplyRatio
     * @dev     performs additional configuration checks and reverts if any condition fails
     * @param   _lpToken a target liquidity token
     */
    function updateSupplyRatio(address _lpToken) external {
        require(permissions[STATUS.LIQUIDITYTOKEN][_lpToken], "Not an LP token");
        require(supplyController[_lpToken] != address(0), "Supply controller is not configured");
        require(ISupplyContoller(supplyController[_lpToken]).supplyControlEnabled(), "Supply controller is not enabled");
        require(ISupplyContoller(supplyController[_lpToken]).paramsSet(), "Supply controller is not initialized");

        _updateSupplyRatio(_lpToken);
    }
    
    /**
     * @notice allow approved Assurance/Parametrics Insurance NFT Treasury to mint Pana from Master Treasury.
     * @param _amount uint256 amount of Pana to mint
     */
    function mintForNFTTreasury(uint256 _amount) external {
        require(permissions[STATUS.NFTTREASURY][msg.sender], notApproved);
        PANA.mint(msg.sender, _amount);
        emit MintedForNFTTreasury(_amount, msg.sender);
    }

    /**
     * @notice allow approved address to withdraw assets
     * @param _token address
     * @param _amount uint256
     */
    function manage(address _token, uint256 _amount) external override {
        if (permissions[STATUS.LIQUIDITYTOKEN][_token]) {
            require(permissions[STATUS.LIQUIDITYMANAGER][msg.sender], notApproved);
        } else {
            require(permissions[STATUS.RESERVEMANAGER][msg.sender], notApproved);
        }

        IERC20(_token).safeTransfer(msg.sender, _amount);
        emit Managed(_token, _amount);
    }

    /**
     * @notice mint new PANA
     * @param _recipient address
     * @param _amount uint256
     */
    function mint(address _recipient, uint256 _amount) external override {
        require(permissions[STATUS.REWARDMANAGER][msg.sender], notApproved);
        PANA.mint(_recipient, _amount);
        emit Minted(msg.sender, _recipient, _amount);
    }

    /**
     * @notice sets new PANA redemption limit
     * @param _limit percentage (as a decimal with 4 precision digits) of PANA balance available for redemption
     */
    function setRedemptionLimit(uint256 _limit) external onlyGovernor {
        require(_limit <= 10000, "Limit cannot exceed 100 percent");
        redemptionLimit = _limit;
    }

    /**
     * @notice enable permission from queue
     * @param _status STATUS
     * @param _address address
     * @param _supplyController address
     */
    function enable(
        STATUS _status,
        address _address,
        address _supplyController
    ) external onlyGovernor {
        require(timelockEnabled == false, "Use queueTimelock");
        if (_status == STATUS.SPANA) {
            sPANA = IsPana(_address);
        } else {
            permissions[_status][_address] = true;

            if (_status == STATUS.LIQUIDITYTOKEN) {
                supplyController[_address] = _supplyController;
            }

            (bool registered, ) = indexInRegistry(_address, _status);
            if (!registered) {
                registry[_status].push(_address);
            }
        }
        emit Permissioned(_address, _status, true);
    }

    /**
     *  @notice disable permission from address
     *  @param _status STATUS
     *  @param _toDisable address
     */
    function disable(STATUS _status, address _toDisable) external {
        require(msg.sender == authority.governor() || msg.sender == authority.guardian(), "Only governor or guardian");
        permissions[_status][_toDisable] = false;
        emit Permissioned(_toDisable, _status, false);
    }

    /**
     * @notice check if registry contains address
     * @return (bool, uint256)
     */
    function indexInRegistry(address _address, STATUS _status) public view returns (bool, uint256) {
        address[] memory entries = registry[_status];
        for (uint256 i = 0; i < entries.length; i++) {
            if (_address == entries[i]) {
                return (true, i);
            }
        }
        return (false, 0);
    }

    /* ========== TIMELOCKED FUNCTIONS ========== */

    // functions are used prior to enabling on-chain governance

    /**
     * @notice queue address to receive permission
     * @param _status STATUS
     * @param _address address
     * @param _supplyController address
     */
    function queueTimelock(
        STATUS _status,
        address _address,
        address _supplyController
    ) external onlyGovernor {
        require(_address != address(0));
        require(timelockEnabled == true, "Timelock is disabled, use enable");

        uint256 timelock = block.number.add(blocksNeededForQueue);
        if (_status == STATUS.RESERVEMANAGER || _status == STATUS.LIQUIDITYMANAGER) {
            timelock = block.number.add(blocksNeededForQueue.mul(2));
        }
        permissionQueue.push(
            Queue({managing: _status, toPermit: _address, supplyController: _supplyController, timelockEnd: timelock, nullify: false, executed: false})
        );
        emit PermissionQueued(_status, _address);
    }

    /**
     *  @notice enable queued permission
     *  @param _index uint256
     */
    function execute(uint256 _index) external {
        require(timelockEnabled == true, "Timelock is disabled, use enable");

        Queue memory info = permissionQueue[_index];

        require(!info.nullify, "Action has been nullified");
        require(!info.executed, "Action has already been executed");
        require(block.number >= info.timelockEnd, "Timelock not complete");

        if (info.managing == STATUS.SPANA) {
            // 9
            sPANA = IsPana(info.toPermit);
        } else {
            permissions[info.managing][info.toPermit] = true;

            if (info.managing == STATUS.LIQUIDITYTOKEN) {
                supplyController[info.toPermit] = info.supplyController;
            }
            (bool registered, ) = indexInRegistry(info.toPermit, info.managing);
            if (!registered) {
                registry[info.managing].push(info.toPermit);

                if (info.managing == STATUS.LIQUIDITYTOKEN) {
                    (bool reg, uint256 index) = indexInRegistry(info.toPermit, STATUS.RESERVETOKEN);
                    if (reg) {
                        delete registry[STATUS.RESERVETOKEN][index];
                    }
                } else if (info.managing == STATUS.RESERVETOKEN) {
                    (bool reg, uint256 index) = indexInRegistry(info.toPermit, STATUS.LIQUIDITYTOKEN);
                    if (reg) {
                        delete registry[STATUS.LIQUIDITYTOKEN][index];
                    }
                }
            }
        }
        permissionQueue[_index].executed = true;
        emit Permissioned(info.toPermit, info.managing, true);
    }

    /**
     * @notice cancel timelocked action
     * @param _index uint256
     */
    function nullify(uint256 _index) external onlyGovernor {
        permissionQueue[_index].nullify = true;
    }

    /**
     * @notice disables timelocked functions
     */
    function disableTimelock() external onlyGovernor {
        require(timelockEnabled == true, "timelock already disabled");
        if (onChainGovernanceTimelock != 0 && onChainGovernanceTimelock <= block.number) {
            timelockEnabled = false;
        } else {
            onChainGovernanceTimelock = block.number.add(blocksNeededForQueue.mul(7)); // 7-day timelock
        }
    }

    /**
     * @notice enables timelocks after initilization
     */
    function initialize() external onlyGovernor {
        require(initialized == false, "Already initialized");
        timelockEnabled = true;
        initialized = true;
    }

    /* ========== VIEW FUNCTIONS ========== */

    /**
     * @notice returns PANA valuation of asset as 1:100
     * The protocol has no intrinsic valuation for external tokens
     * This function values any given asset at 100 PANA
     * Only to be used for valuation of RESERVE TOKENS
     * Not to be used to valuate LP tokens
     * @param _token address
     * @param _amount uint256
     * @return value_ uint256
     */
    function tokenValue(address _token, uint256 _amount) public view override returns (uint256 value_) {
        require(permissions[STATUS.RESERVETOKEN][_token], noValuation);

        value_ = _amount.mul(1e11).mul(10**IERC20Metadata(address(PANA)).decimals())
                            .div(10**9).div(10**IERC20Metadata(_token).decimals());
    }

    /**
     * @notice returns supply metric
     * @dev use this any time you need to query supply
     * @return uint256
     */
    function baseSupply() external view override returns (uint256) {
        return PANA.totalSupply();
    }

    /**
     * @notice returns current amount of PANA available for redemption
     * @return uint256
     */
    function availableForRedemption() public view returns (uint256) {
        return PANA.balanceOf(address(this)).mul(redemptionLimit).div(10**4);
    }
}

