// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "./Ownable.sol";
import "./Pausable.sol";

contract StratManager is Ownable, Pausable {
    /// @dev SteakHut Contracts:
    /// {keeper} - Address to manage a few lower risk features of the strat incl rebalancing
    /// {strategist} - Address of the strategy author/deployer where strategist fee will go.
    /// {vault} - Address of the vault that controls the strategy's funds.
    /// {joeRouter} - Address of exchange to execute swaps.
    address public keeper;
    address public strategist;
    address public joeRouter;
    address public vault;
    address public feeRecipient;

    /// -----------------------------------------------------------
    /// Events
    /// -----------------------------------------------------------
    event SetKeeper(address keeper);
    event SetStrategist(address strategist);
    event SetFeeRecipient(address feeRecipient);
    event SetJoeRouter(address joeRouter);

    /**
     * @dev Initializes the base strategy.
     * @param _keeper address to use as alternative owner.
     * @param _strategist address where strategist fees go.
     * @param _joeRouter router to use for swaps
     * @param _vault address of parent vault.
     * @param _feeRecipient address where to send SteakHut's fees.
     */
    constructor(
        address _keeper,
        address _strategist,
        address _joeRouter,
        address _vault,
        address _feeRecipient
    ) {
        keeper = _keeper;
        strategist = _strategist;
        joeRouter = _joeRouter;
        vault = _vault;
        feeRecipient = _feeRecipient;
    }

    // checks that caller is either owner or keeper.
    modifier onlyManager() {
        require(msg.sender == owner() || msg.sender == keeper, "!manager");
        _;
    }

    /// @notice Updates address of the strat keeper.
    /// @param _keeper new keeper address.
    function setKeeper(address _keeper) external onlyManager {
        require(_keeper != address(0), "StratManager: 0 address");
        keeper = _keeper;

        emit SetKeeper(_keeper);
    }

    /// @notice Updates address where strategist fee earnings will go.
    /// @param _strategist new strategist address.
    function setStrategist(address _strategist) external {
        require(msg.sender == strategist, "!strategist");
        require(_strategist != address(0), "StratManager: 0 address");
        strategist = _strategist;

        emit SetStrategist(_strategist);
    }

    /// @notice Updates router that will be used for swaps.
    /// @param _joeRouter new joeRouter address.
    function setJoeRouter(address _joeRouter) external onlyOwner {
        require(_joeRouter != address(0), "StratManager: 0 address");
        joeRouter = _joeRouter;

        emit SetJoeRouter(_joeRouter);
    }

    /// @notice updates SteakHut fee recipient (i.e multsig)
    /// @param _feeRecipient new SteakHut fee recipient address.
    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        require(_feeRecipient != address(0), "StratManager: 0 address");
        feeRecipient = _feeRecipient;

        emit SetFeeRecipient(_feeRecipient);
    }

    /// @notice Function to synchronize balances before new user deposit.
    /// Can be overridden in the strategy.
    function beforeDeposit() external virtual {}
}

