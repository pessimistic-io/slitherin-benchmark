// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;
import "./IFutureVault.sol";
import "./IRegistry.sol";

interface IController {
    /* Events */

    event NextPeriodSwitchSet(
        uint256 indexed _periodDuration,
        uint256 _nextSwitchTimestamp
    );
    event NewPeriodDurationIndexSet(uint256 indexed _periodIndex);
    event FutureRegistered(IFutureVault indexed _futureVault);
    event FutureUnregistered(IFutureVault indexed _futureVault);
    event StartingDelaySet(uint256 _startingDelay);
    event FutureTerminated(IFutureVault indexed _futureVault);
    event DepositsPaused(IFutureVault _futureVault);
    event DepositsResumed(IFutureVault _futureVault);
    event WithdrawalsPaused(IFutureVault _futureVault);
    event WithdrawalsResumed(IFutureVault _futureVault);
    event FutureSetToBeTerminated(IFutureVault _futureVault);

    /* Params */

    function STARTING_DELAY() external view returns (uint256);

    /* User Methods */

    /**
     * @notice Deposit funds into ongoing period
     * @param _futureVault the address of the futureVault to be deposit the funds in
     * @param _amount the amount to deposit on the ongoing period
     * @dev part of the amount depostied will be used to buy back the yield already generated proportionaly to the amount deposited
     */
    function deposit(IFutureVault _futureVault, uint256 _amount) external;

    function depositForUser(
        IFutureVault _futureVault,
        address _user,
        uint256 _amount
    ) external;

    /**
     * @notice Withdraw deposited funds from APWine
     * @param _futureVault the address of the futureVault to withdraw the IBT from
     * @param _amount the amount to withdraw
     */
    function withdraw(IFutureVault _futureVault, uint256 _amount) external;

    /**
     * @notice Exit a terminated pool
     * @param _futureVault the address of the futureVault to exit from from
     * @dev only pt are required as there  aren't any new FYTs
     */
    function exitTerminatedFuture(IFutureVault _futureVault) external;

    /**
     * @notice Create a delegation from one address to another for a futureVault
     * @param _futureVault the corresponding futureVault address
     * @param _receiver the address receiving the futureVault FYTs
     * @param _amount the of futureVault FYTs to delegate
     */
    function createFYTDelegationTo(
        IFutureVault _futureVault,
        address _receiver,
        uint256 _amount
    ) external;

    /**
     * @notice Remove a delegation from one address to another for a futureVault
     * @param _futureVault the corresponding futureVault address
     * @param _receiver the address receiving the futureVault FYTs
     * @param _amount the of futureVault FYTs to remove from the delegation
     */
    function withdrawFYTDelegationFrom(
        IFutureVault _futureVault,
        address _receiver,
        uint256 _amount
    ) external;

    /**
     * @notice Register a newly created futureVault in the registry
     * @param _futureVault the interface of the new futureVault
     */
    function registerNewFutureVault(IFutureVault _futureVault) external;

    /**
     * @notice Unregister a futureVault from the registry
     * @param _futureVault the interface of the futureVault to unregister
     */
    function unregisterFutureVault(IFutureVault _futureVault) external;

    /**
     * @notice Change the delay for starting a new period
     * @param _startingDelay the new delay (+-) to start the next period
     */
    function setPeriodStartingDelay(uint256 _startingDelay) external;

    /**
     * @notice Start a specific future
     * @param _futureVault the interface of the futureVault to start
     * @dev should not be called if planning to use startFuturesByPeriodDuration in the same period
     */
    function startFuture(IFutureVault _futureVault) external;

    /**
     * @notice Set the next period switch timestamp for the futureVault with corresponding duration
     * @param _periodDuration the period duration
     * @param _nextPeriodTimestamp the next period switch timestamp
     */
    function setNextPeriodSwitchTimestamp(
        uint256 _periodDuration,
        uint256 _nextPeriodTimestamp
    ) external;

    /**
     * @notice Set the next period duration index
     * @param _periodDuration the period duration
     * @param _newPeriodIndex the next period duration index
     * @dev should only be called if there is a need of arbitrarily chaging the indexes in the FYT/PT naming
     */
    function setPeriodDurationIndex(
        uint256 _periodDuration,
        uint256 _newPeriodIndex
    ) external;

    /**
     * @notice Start all futures that have a defined period duration to synchronize them
     * @param _periodDuration the period duration of the futures to start
     */
    function startFuturesByPeriodDuration(uint256 _periodDuration) external;

    /* Getters */

    /**
     * @notice Getter for the registry address of the protocol
     * @return the address of the protocol registry
     */
    function getRegistryAddress() external view returns (address);

    /**
     * @notice Getter for the period index depending on the period duration of the futureVault
     * @param _periodDuration the duration of the periods
     * @return the period index
     */
    function getPeriodIndex(uint256 _periodDuration)
        external
        view
        returns (uint256);

    /**
     * @notice Getter for the beginning timestamp of the next period for the futures with a defined period duration
     * @param _periodDuration the duration of the periods
     * @return the timestamp of the beginning of the next period
     */
    function getNextPeriodStart(uint256 _periodDuration)
        external
        view
        returns (uint256);

    /**
     * @notice Getter for the list of futureVault durations registered in the contract
     * @return durationsList which consists of futureVault durations
     */
    function getDurations()
        external
        view
        returns (uint256[] memory durationsList);

    /**
     * @notice Getter for the futures by period duration
     * @param _periodDuration the period duration of the futures to return
     */
    function getFuturesWithDuration(uint256 _periodDuration)
        external
        view
        returns (address[] memory filteredFutures);

    /* Security functions */

    /**
     * @notice Terminate a futureVault
     * @param _futureVault the interface of the futureVault to terminate
     * @dev should only be called in extraordinary situations by the admin of the contract
     */
    function setFutureToTerminate(IFutureVault _futureVault) external;

    /**
     * @notice Getter for the futureVault period state
     * @param _futureVault the address of the futureVault
     * @return true if the futureVault is terminated
     */
    function isFutureTerminated(address _futureVault)
        external
        view
        returns (bool);

    /**
     * @notice Getter for the futureVault period state
     * @param _futureVault the address of the futureVault
     * @return true if the futureVault is set to be terminated at its expiration
     */
    function isFutureSetToBeTerminated(address _futureVault)
        external
        view
        returns (bool);

    /**
     * @notice Getter for the futureVault withdrawals state
     * @param _futureVault the address of the futureVault
     * @return true is new withdrawals are paused, false otherwise
     */
    function isWithdrawalsPaused(address _futureVault)
        external
        view
        returns (bool);

    /**
     * @notice Getter for the futureVault deposits state
     * @param _futureVault the address of the futureVault
     * @return true is new deposits are paused, false otherwise
     */
    function isDepositsPaused(address _futureVault)
        external
        view
        returns (bool);

    /* Future Vault rewards mechanism */

    function harvestVaultRewards(IFutureVault _futureVault) external;

    function redeemVaultRewards(IFutureVault _futureVault, address _rewardToken)
        external;

    function redeemAllVaultRewards(IFutureVault _futureVault) external;

    function harvestWalletRewards(IFutureVault _futureVault) external;

    function redeemAllWalletRewards(IFutureVault _futureVault) external;

    function redeemWalletRewards(
        IFutureVault _futureVault,
        address _rewardToken
    ) external;
}

