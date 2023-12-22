// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./OwnableUpgradeable.sol";
import "./PausableUpgradeable.sol";

/**
 * @title StratManager
 * @dev This contract manages the strategy fees and related addresses.
 */
contract StratManager is OwnableUpgradeable, PausableUpgradeable {

    uint256 public constant FEE_SCALE = 1e18;
    uint256 public constant SLIPPAGE_SCALE = 10000;

    address public keeper;
    address public manager;
    address public swapRouter;
    address public factorFeeRecipient;
    address public strategist;

    uint256 public performanceFee;
    uint256 public factorFee;
    uint256 public strategistFee;
    uint256 public callFee;
    uint256 public withdrawFee;
    uint256 public depositFee;
    uint256 public slippage;

    event SetFactorFeeRecipient(address factorFeeRecipient);
    event SetManager(address manager);
    event SetSwapRouter(address swapRouter);
    event SetStrategist(address strategist);
    event SetWithdrawFee(uint256 withdrawFee);
    event SetDepositFee(uint256 depositFee);
    event SetPerformanceFee(uint256 performanceFee);
    event SetFactorFee(uint256 factorFee);
    event SetStrategistFee(uint256 strategistFee);
    event SetCallFee(uint256 callFee);
    event SetSlippage(uint256 slippage);

    // Initialization parameters struct
    struct StratFeeManagerParams {
        address swapRouter;
        address manager;
        address factorFeeRecipient;
        address keeper;
        address strategist;
    }

    /**
     * @dev Initializes the contract with initial values.
     * @param params Struct containing the required initialization parameters.
     */
    function __StratFeeManager_init(StratFeeManagerParams calldata params) internal onlyInitializing {
        __Ownable_init();
        require(params.swapRouter != address(0), "Invalid swapRouter address");
        require(params.manager != address(0), "Invalid manager address");
        require(params.factorFeeRecipient != address(0), "Invalid factorFeeRecipient address");
        require(params.keeper != address(0), "Invalid keeper address");
        require(params.strategist != address(0), "Invalid strategist address");
        swapRouter = params.swapRouter;
        manager = params.manager;
        factorFeeRecipient = params.factorFeeRecipient;
        keeper = params.keeper;
        strategist = params.strategist;
        withdrawFee = 1e16;
        performanceFee = 1e16;
        depositFee = 1e16;
        factorFee = 1e16;
        strategistFee = 1e16;
        callFee = 1e16;
        slippage = 100;
    }

    modifier onlyManager() {
        require(msg.sender == owner() || msg.sender == manager, "!manager");
        _;
    }

    modifier onlyKeeper() {
        require(msg.sender == owner() || msg.sender == keeper, "!keeper");
        _;
    }

    /**
     * @dev Set the keeper address.
     */
    function setKeeper(address _keeper) external onlyManager {
        keeper = _keeper;
        emit SetManager(_keeper);
    }

    /**
     * @dev Set the manager address.
     */
    function setManager(address _manager) external onlyManager {
        manager = _manager;
        emit SetManager(_manager);
    }

    /**
     * @dev Set the swap router address.
     */
    function setSwaprouter(address _swapRouter) external onlyOwner {
        swapRouter = _swapRouter;
        emit SetSwapRouter(_swapRouter);
    }

    /**
     * @dev Set the factor fee recipient address.
     */
    function setFactorFeeRecipient(address _factorFeeRecipient) external onlyOwner {
        factorFeeRecipient = _factorFeeRecipient;
        emit SetFactorFeeRecipient(_factorFeeRecipient);
    }

    /**
     * @dev Set the strategist address.
    */
    function setStrategist(address _strategist) external {
        require(msg.sender == strategist, "!strategist");
        strategist = _strategist;
        emit SetStrategist(_strategist);
    }

    /**
    * @dev Set the performance fee.
    */
    function setPerformanceFee(uint256 _performanceFee) external onlyManager {
        require(_performanceFee <= FEE_SCALE, "Invalid fee");
        performanceFee = _performanceFee;
        emit SetPerformanceFee(_performanceFee);
    }

    /**
    * @dev Set the withdraw fee.
    */
    function setWithdrawFee(uint256 _withdrawFee) public onlyManager {
        require(_withdrawFee <= FEE_SCALE, "Invalid fee");
        withdrawFee = _withdrawFee;
        emit SetWithdrawFee(_withdrawFee);
    }

    /**
    * @dev Set the deposit fee.
    */
    function setDepositFee(uint256 _depositFee) external onlyManager {
        require(_depositFee <= FEE_SCALE, "Invalid fee");
        depositFee = _depositFee;
        emit SetDepositFee(_depositFee);
    }

    /**
    * @dev Set the factor fee.
    */
    function setFactorFee(uint256 _factorFee) external onlyManager {
        require(_factorFee <= FEE_SCALE, "Invalid fee");
        factorFee = _factorFee;
        emit SetFactorFee(_factorFee);
    }

    /**
    * @dev Set the strategist fee.
    */
    function setStrategistFee(uint256 _strategistFee) external onlyManager {
        require(_strategistFee <= FEE_SCALE, "Invalid fee");
        strategistFee = _strategistFee;
        emit SetStrategistFee(_strategistFee);
    }

    /**
    * @dev Set the call fee.
    */
    function setCallFee(uint256 _callFee) external onlyManager {
        require(_callFee <= FEE_SCALE, "Invalid fee");
        callFee = _callFee;
        emit SetCallFee(_callFee);
    }

    /**
    * @dev Set the slippage for swap.
    */
    function setSlippage(uint256 _slippage) external onlyManager {
        require(_slippage <= SLIPPAGE_SCALE, "Invalid slippage");
        slippage = _slippage;
        emit SetSlippage(_slippage);
    }

    uint256[38] private __gap;

}
