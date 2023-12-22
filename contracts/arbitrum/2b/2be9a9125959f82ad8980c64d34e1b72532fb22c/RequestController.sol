// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

import "./IRequestController.sol";
import "./RequestControllerAdmin.sol";
import "./RequestControllerEvents.sol";
import "./RequestControllerMessageHandler.sol";
import "./CommonModifiers.sol";
import "./IPToken.sol";

import "./Initializable.sol";
import "./UUPSUpgradeable.sol";

contract RequestController is
    IRequestController,
    RequestControllerAdmin,
    RequestControllerMessageHandler,
    Initializable,
    UUPSUpgradeable
{

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() AdminControl(msg.sender) {}

    function initialize(
        uint256 _masterCID
    ) external payable initializer() {
        __UUPSUpgradeable_init();

        setContractIdentifier(REQUEST_CONTROLLER_IDENTIFIER);

        masterCID = _masterCID;

        admin = payable(msg.sender);
    }

    function _authorizeUpgrade(address) internal override onlyAdmin() {}

    /**
     * @notice Users deposits funds for pTokens in exchange
     * @param pTokenAddress The address of the pToken contract the user wishes to deposit to
     * @param route Route through which to request to deposit tokens
     * @param user The address of the user wishing to deposit
     * @param amount The amount the user wishes to deposit
    */
    function deposit(
        address route,
        address user,
        uint256 amount,
        address pTokenAddress
    ) external override payable virtual {
        if (block.chainid == masterCID && uint256(gasleft()) < uint256(800000)) revert GasLimitTooLow(uint256(gasleft()));
        if (pTokenAddress == address(0)) revert AddressExpected();
        if (user == address(0)) revert AddressExpected();
        if (user != msg.sender) revert OnlyAccount();

        IPToken(pTokenAddress).depositBehalf{value: msg.value}(route, user, amount);
    }

    /**
    * @notice Depositor withdraws pTokens in exchange for a specified amount of underlying asset
    * @param withdrawAmount The amount of pToken to withdraw from the protocol
    * @param route Route through which to request to withdraw tokens
    */
    function withdraw(
        address route,
        uint256 withdrawAmount,
        address pToken,
        uint256 targetChainId
    ) external override payable nonReentrant() {
        if (withdrawAmount == 0) revert ExpectedWithdrawAmount();
        if (isPTokenFrozen[pToken]) revert PTokenIsFrozen(pToken);
        if (targetChainId == 0) revert ChainIdExpected();

        _sendWithdraw(
            msg.sender,
            route,
            withdrawAmount,
            pToken,
            targetChainId
        );
    }

    /**
     * @notice Users borrow assets from a supported loan market
     * @param borrowAmount The amount of the loan market asset to borrow
     * @param loanMarketAsset The asset to borrow
     */
    function borrow(
        address route,
        address loanMarketAsset,
        uint256 borrowAmount,
        uint256 targetChainId
    ) external payable virtual override {
        if (borrowAmount == 0) revert ExpectedBorrowAmount();
        if (loanMarketAsset == address(0)) revert AddressExpected();
        if (isLoanMarketFrozen[loanMarketAsset]) revert MarketIsFrozen(loanMarketAsset);
        if (isdeprecated[loanMarketAsset]) revert MarketIsdeprecated(loanMarketAsset);
        if (targetChainId == 0) revert ChainIdExpected();

        _sendBorrow(
            msg.sender,
            route,
            loanMarketAsset,
            borrowAmount,
            targetChainId
        );
    }

    /**
     * @notice Users repay a loan on their own behalf
     * @param repayAmount The amount of the loan market asset to repay
     * @param loanMarketAsset The asset to repay
    */
    function repayBorrow(
        address route,
        address loanMarketAsset,
        uint256 repayAmount
    ) external payable virtual override returns (uint256) {
        if (block.chainid == masterCID && uint256(gasleft()) < uint256(800000)) revert GasLimitTooLow(uint256(gasleft()));
        if (repayAmount == 0) revert ExpectedRepayAmount();
        if (loanMarketAsset == address(0)) revert AddressExpected();
        if (isLoanMarketFrozen[loanMarketAsset]) revert MarketIsFrozen(loanMarketAsset);

        return _sendRepay(
            msg.sender,
            msg.sender,
            route,
            loanMarketAsset,
            repayAmount
        );
    }

    /**
     * @notice Users repay a loan on behalf of another
     * @param borrower The person the loan is repaid on behalf of
     * @param repayAmount The amount of the loan market asset to repay
     * @param loanMarketAsset The asset to repay
    */
    function repayBorrowBehalf(
        address borrower,
        address route,
        address loanMarketAsset,
        uint256 repayAmount
    ) external payable virtual override returns (uint256) {
        if (block.chainid == masterCID && uint256(gasleft()) < uint256(800000)) revert GasLimitTooLow(uint256(gasleft()));
        if (repayAmount == 0) revert ExpectedRepayAmount();
        if (loanMarketAsset == address(0)) revert AddressExpected();
        if (isLoanMarketFrozen[loanMarketAsset]) revert MarketIsFrozen(loanMarketAsset);

        return _sendRepay(
            msg.sender,
            borrower,
            route,
            loanMarketAsset,
            repayAmount
        );
    }

    function liquidate(
        address route,
        address seizeToken, // asset the liquidator will be repaid on
        uint256 seizeTokenChainId, // chainId of the tokens to seize
        address borrower, // address of the user being liquidated
        address loanAsset, // asset to be repaid on local chain
        uint256 repayAmount // amount of asset to be repaid by liquidator right now on local chain
    ) external payable /* override */ {
        if (block.chainid == masterCID && uint256(gasleft()) < uint256(800000)) revert GasLimitTooLow(uint256(gasleft()));
        if (repayAmount == 0) revert ExpectedRepayAmount();

        uint256 _value;
        uint256 _gas = msg.value;
        {
            (bool success, bytes memory ret) = loanAsset.staticcall(
                abi.encodeWithSignature(
                    "underlying()"
                )
            );
            if (success) {
                (address underlying) = abi.decode(ret, (address));
                if (underlying == address(0)) {
                    _value = repayAmount;
                    _gas -= _value;
                }
            }
        }
        ILendable(loanAsset).processRepay{value: _value}(msg.sender, repayAmount);

        // send the liquidation
        _sendLiquidation(
            borrower,
            route,
            seizeToken,
            seizeTokenChainId,
            loanAsset,
            repayAmount,
            _gas
        );
    }
}

