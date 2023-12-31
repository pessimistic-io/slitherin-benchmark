//   ______
//  /      \
// /$$$$$$  | __    __  __    __   ______
// $$ |__$$ |/  |  /  |/  \  /  | /      \
// $$    $$ |$$ |  $$ |$$  \/$$/ /$$$$$$  |
// $$$$$$$$ |$$ |  $$ | $$  $$<  $$ |  $$ |
// $$ |  $$ |$$ \__$$ | /$$$$  \ $$ \__$$ |
// $$ |  $$ |$$    $$/ /$$/ $$  |$$    $$/
// $$/   $$/  $$$$$$/  $$/   $$/  $$$$$$/
//
// auxo.fi

// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.12;

import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {Pausable} from "./Pausable.sol";

import {IVault} from "./IVault.sol";
import {IHubPayload} from "./IHubPayload.sol";
import {IStrategy} from "./IStrategy.sol";

import {XChainHubStorage} from "./XChainHubStorage.sol";
import {XChainHubEvents} from "./XChainHubEvents.sol";

import {LayerZeroApp} from "./LayerZeroApp.sol";
import {LayerZeroAdapter} from "./LayerZeroAdapter.sol";
import {IStargateReceiver} from "./IStargateReceiver.sol";
import {IStargateRouter} from "./IStargateRouter.sol";

/// @title XChainHub Source
/// @notice Grouping of XChainHub functions on the source chain
/// @dev source refers to the chain initially sending XChain deposits
abstract contract XChainHubSrc is Pausable, LayerZeroAdapter, XChainHubStorage, XChainHubEvents {
    using SafeERC20 for IERC20;

    constructor(address _stargateRouter) {
        stargateRouter = IStargateRouter(_stargateRouter);
    }

    /// ------------------------
    /// Single Chain Functions
    /// ------------------------

    /// @notice restricts external approval calls to the owner
    function approveWithdrawalForStrategy(address _strategy, IERC20 underlying, uint256 _amount) external onlyOwner {
        _approveWithdrawalForStrategy(_strategy, underlying, _amount);
    }

    /// @notice approve a strategy to withdraw tokens from the hub
    /// @dev call before withdrawing from the strategy
    /// @param _strategy the address of the XChainStrategy on this chain
    /// @param underlying the token
    /// @param _amount the quantity to approve
    function _approveWithdrawalForStrategy(address _strategy, IERC20 underlying, uint256 _amount) internal {
        require(trustedStrategy[_strategy], "XChainHub::approveWithdrawalForStrategy:UNTRUSTED");
        /// @dev safe approve is deprecated
        underlying.safeApprove(_strategy, _amount);
    }

    // --------------------------
    // Cross Chain Functions
    // --------------------------

    /// @notice iterates through a list of destination chains and sends the current value of
    ///         the strategy (in terms of the underlying vault token) to that chain.
    /// @param _vault Vault on the current chain.
    /// @param _dstChains is an array of the layerZero chain Ids to check
    /// @param _strats array of strategy addresses on the destination chains, index should match the dstChainId
    /// @param _dstGas required on dstChain for operations
    /// @dev There are a few caveats:
    ///       - All strategies must have deposits.
    ///       - Strategies must be trusted
    ///       - The list of chain ids and strategy addresses must be the same length, and use the same underlying token.
    function lz_reportUnderlying(
        IVault _vault,
        uint16[] memory _dstChains,
        address[] memory _strats,
        uint256 _dstGas,
        address payable _refundAddress
    )
        external
        payable
        onlyOwner
        whenNotPaused
    {
        require(REPORT_DELAY > 0, "XChainHub::reportUnderlying:SET DELAY");
        require(trustedVault[address(_vault)], "XChainHub::reportUnderlying:UNTRUSTED");
        require(_dstChains.length == _strats.length, "XChainHub::reportUnderlying:LENGTH MISMATCH");

        uint256 amountToReport;
        uint256 exchangeRate = _vault.exchangeRate();

        for (uint256 i; i < _dstChains.length; i++) {
            uint256 shares = sharesPerStrategy[_dstChains[i]][_strats[i]];

            /// @dev: we explicitly check for zero deposits withdrawing
            /// TODO check whether we need this, for now it is commented
            // require(shares > 0, "XChainHub::reportUnderlying:NO DEPOSITS");

            require(
                block.timestamp >= latestUpdate[_dstChains[i]][_strats[i]] + REPORT_DELAY,
                "XChainHub::reportUnderlying:TOO RECENT"
            );

            // record the latest update for future reference
            latestUpdate[_dstChains[i]][_strats[i]] = block.timestamp;

            amountToReport = (shares * exchangeRate) / 10 ** _vault.decimals();

            IHubPayload.Message memory message = IHubPayload.Message({
                action: REPORT_UNDERLYING_ACTION,
                payload: abi.encode(IHubPayload.ReportUnderlyingPayload({strategy: _strats[i], amountToReport: amountToReport}))
            });

            _lzSend(
                _dstChains[i],
                abi.encode(message),
                _refundAddress,
                address(0), // zro address (not used)
                abi.encodePacked(uint8(1), _dstGas) // version 1 only accepts dstGas
            );

            emit UnderlyingReported(_dstChains[i], amountToReport, _strats[i]);
        }
    }

    /// @notice approve transfer to the stargate router
    /// @dev stack too deep prevents keeping in function below
    function _approveRouterTransfer(address _sender, uint256 _amount) internal {
        IStrategy strategy = IStrategy(_sender);
        IERC20 underlying = strategy.underlying();

        underlying.safeTransferFrom(_sender, address(this), _amount);
        underlying.safeApprove(address(stargateRouter), _amount);
    }

    /// @dev Only Called by the Cross Chain Strategy
    /// @notice makes a deposit of the underyling token into the vault on a given chain
    /// @param _params a stuct encoding the deposit paramters
    function sg_depositToChain(IHubPayload.SgDepositParams calldata _params) external payable whenNotPaused {
        require(trustedStrategy[msg.sender], "XChainHub::depositToChain:UNTRUSTED");

        bytes memory dstHub = trustedRemoteLookup[_params.dstChainId];

        require(dstHub.length != 0, "XChainHub::finalizeWithdrawFromChain:NO HUB");

        // load some variables into memory
        uint256 amount = _params.amount;
        address dstVault = _params.dstVault;

        _approveRouterTransfer(msg.sender, amount);

        IHubPayload.Message memory message = IHubPayload.Message({
            action: DEPOSIT_ACTION,
            payload: abi.encode(IHubPayload.DepositPayload({vault: dstVault, strategy: msg.sender, amountUnderyling: amount}))
        });

        stargateRouter.swap{value: msg.value}(
            _params.dstChainId,
            _params.srcPoolId,
            _params.dstPoolId,
            _params.refundAddress,
            amount,
            _params.minOut,
            IStargateRouter.lzTxObj({
                dstGasForCall: _params.dstGas,
                dstNativeAmount: 0,
                dstNativeAddr: abi.encodePacked(address(0x0))
            }),
            dstHub, // This hub must implement sgReceive
            abi.encode(message)
        );
        emit DepositSent(_params.dstChainId, amount, dstHub, dstVault, msg.sender);
    }

    /// @notice Only called by x-chain Strategy
    /// @dev IMPORTANT you need to add the dstHub as a trustedRemote on the src chain BEFORE calling
    ///      any layerZero functions. Call `setTrustedRemote` on this contract as the owner
    ///      with the params (dstChainId - LAYERZERO, dstHub address)
    /// @notice make a request to withdraw tokens from a vault on a specified chain
    ///         the actual withdrawal takes place once the batch burn process is completed
    /// @param _dstChainId the layerZero chain id on destination
    /// @param _dstVault address of the vault on destination
    /// @param _amountVaultShares the number of auxovault shares to burn for underlying
    /// @param _refundAddress addrss on the source chain to send rebates to
    /// @param _dstGas required on dstChain for operations
    function lz_requestWithdrawFromChain(
        uint16 _dstChainId,
        address _dstVault,
        uint256 _amountVaultShares,
        address payable _refundAddress,
        uint256 _dstGas
    )
        external
        payable
        whenNotPaused
    {
        require(trustedStrategy[msg.sender], "XChainHub::requestWithdrawFromChain:UNTRUSTED");
        require(_dstVault != address(0x0), "XChainHub::requestWithdrawFromChain:NO DST VAULT");

        IHubPayload.Message memory message = IHubPayload.Message({
            action: REQUEST_WITHDRAW_ACTION,
            payload: abi.encode(
                IHubPayload.RequestWithdrawPayload({vault: _dstVault, strategy: msg.sender, amountVaultShares: _amountVaultShares})
                )
        });

        _lzSend(
            _dstChainId,
            abi.encode(message),
            _refundAddress,
            address(0), // the address of the ZRO token holder who would pay for the transaction
            abi.encodePacked(uint8(1), _dstGas) // version 1 only accepts dstGas
        );

        emit WithdrawRequested(_dstChainId, _amountVaultShares, _dstVault, msg.sender);
    }

    function _getTrustedHub(uint16 _srcChainId) internal view returns (address) {
        address hub;
        bytes memory _h = trustedRemoteLookup[_srcChainId];
        assembly {
            hub := mload(_h)
        }
        return hub;
    }

    function _approveRouter(address _vault, uint256 _amount) internal {
        IVault vault = IVault(_vault);
        IERC20 underlying = vault.underlying();
        underlying.safeApprove(address(stargateRouter), _amount);
    }

    /// @notice sends tokens withdrawn from local vault to a remote hub
    /// @param _params struct encoding arguments
    function sg_finalizeWithdrawFromChain(IHubPayload.SgFinalizeParams calldata _params)
        external
        payable
        whenNotPaused
        onlyOwner
    {
        /// @dev passing manually at the moment
        // uint256 currentRound = currentRoundPerStrategy[_dstChainId][_strategy];

        bytes memory dstHub = trustedRemoteLookup[_params.dstChainId];
        uint256 strategyAmount = withdrawnPerRound[_params.vault][_params.currentRound];

        require(dstHub.length != 0, "XChainHub::finalizeWithdrawFromChain:NO HUB");
        require(_params.currentRound > 0, "XChainHub::finalizeWithdrawFromChain:NO ACTIVE ROUND");
        require(!exiting[_params.vault], "XChainHub::finalizeWithdrawFromChain:EXITING");
        require(trustedVault[_params.vault], "XChainHub::finalizeWithdrawFromChain:UNTRUSTED VAULT");
        require(strategyAmount > 0, "XChainHub::finalizeWithdrawFromChain:NO WITHDRAWS");

        _approveRouter(_params.vault, strategyAmount);
        currentRoundPerStrategy[_params.dstChainId][_params.strategy] = 0;
        exitingSharesPerStrategy[_params.dstChainId][_params.strategy] = 0;

        IHubPayload.Message memory message = IHubPayload.Message({
            action: FINALIZE_WITHDRAW_ACTION,
            payload: abi.encode(IHubPayload.FinalizeWithdrawPayload({vault: _params.vault, strategy: _params.strategy}))
        });
        stargateRouter.swap{value: msg.value}(
            _params.dstChainId,
            _params.srcPoolId,
            _params.dstPoolId,
            _params.refundAddress,
            strategyAmount,
            _params.minOutUnderlying,
            IStargateRouter.lzTxObj({
                dstGasForCall: _params.dstGas,
                dstNativeAmount: 0,
                dstNativeAddr: abi.encodePacked(address(0x0))
            }),
            dstHub,
            abi.encode(message)
        );

        emit WithdrawalSent(
            _params.dstChainId, strategyAmount, dstHub, _params.vault, _params.strategy, _params.currentRound
            );
    }
}

