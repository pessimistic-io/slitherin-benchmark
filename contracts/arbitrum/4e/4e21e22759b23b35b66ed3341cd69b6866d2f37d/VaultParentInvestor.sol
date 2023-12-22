// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import { ITransport } from "./ITransport.sol";
import { VaultOwnership } from "./VaultOwnership.sol";
import { Registry } from "./Registry.sol";
import { VaultParentStorage } from "./VaultParentStorage.sol";
import { VaultParentInternal } from "./VaultParentInternal.sol";
import { VaultBaseInternal } from "./VaultBaseInternal.sol";

import { Constants } from "./Constants.sol";

import { IERC20 } from "./IERC20.sol";
import { SafeERC20 } from "./SafeERC20.sol";

contract VaultParentInvestor is VaultParentInternal {
    using SafeERC20 for IERC20;

    modifier isInSync() {
        require(inSync(), 'not synced');
        _;
    }

    function initialize(
        string memory _name,
        string memory _symbol,
        address _manager,
        uint _managerStreamingFeeBasisPoints,
        uint _managerPerformanceFeeBasisPoints,
        Registry _registry
    ) external {
        VaultParentStorage.Layout storage l = VaultParentStorage.layout();
        require(l.vaultId == 0, 'already initialized');

        l.vaultId = keccak256(
            abi.encodePacked(_registry.chainId(), address(this))
        );

        VaultBaseInternal.initialize(_registry, _manager);
        VaultOwnership.initialize(
            _name,
            _symbol,
            _manager,
            _managerStreamingFeeBasisPoints,
            _managerPerformanceFeeBasisPoints,
            _registry.protocolTreasury()
        );
    }

    function getSendQuote(
        bytes4 sigHash,
        uint16 chainId
    ) external view returns (uint fee) {
        return _getSendQuote(sigHash, chainId);
    }

    function getSendQuoteMultiChain(
        bytes4 sigHash,
        uint16[] memory chainIds
    ) external view returns (uint[] memory fees, uint256 totalSendFee) {
        return _getSendQuoteMultiChain(sigHash, chainIds);
    }

    function getVaultValue() external view returns (uint value) {
        return _getVaultValue();
    }

    function childChains(uint index) public view returns (uint16) {
        VaultParentStorage.Layout storage l = VaultParentStorage.layout();

        return l.childChains[index];
    }

    function children(uint16 chainId) public view returns (address) {
        return _children(chainId);
    }

    function totalValueAcrossAllChains() external view returns (uint value) {
        return _totalValueAcrossAllChains();
    }

    function deposit(uint tokenId, address asset, uint amount) external {
        _deposit(tokenId, asset, amount);
    }

    function _deposit(
        uint tokenId,
        address asset,
        uint amount
    ) internal noBridgeInProgress noWithdrawInProgress isInSync {
        uint totalVaultValue = _totalValueAcrossAllChains();
        if (_totalShares() > 0 && totalVaultValue == 0) {
            // This means all the shares issue are currently worthless
            // We can't issue anymore shares
            revert('vault closed');
        }
        uint depositValue = _registry().accountant().assetValue(asset, amount);
        // require(depositValue >= baseUnitPrice * 50, 'must deposit > 50 USD');
        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);

        uint shares;
        uint currentUnitPrice;
        if (_totalShares() == 0) {
            shares = depositValue;
            // We should debate if the base unit of the vaults is to be 10**18 or 10**8.
            // 10**8 is the natural unit for USD (which is what the unitPrice is denominated in), but 10**18 gives us more precision when it comes to leveling fees.
            currentUnitPrice =
                (depositValue * Constants.VAULT_PRECISION) /
                depositValue;
        } else {
            shares = (depositValue * _totalShares()) / totalVaultValue;
            currentUnitPrice =
                (totalVaultValue * Constants.VAULT_PRECISION) /
                _totalShares();
        }

        _updateActiveAsset(asset);
        _issueShares(
            tokenId,
            msg.sender,
            shares,
            currentUnitPrice,
            _registry().depositLockupTime()
        );
    }

    function withdraw(uint tokenId, uint amount) external payable {
        _withdraw(tokenId, amount);
    }

    function withdrawAll(uint tokenId) external payable {
        _withdrawAll(tokenId);
    }

    function _withdrawAll(uint tokenId) internal {
        _levyFees(tokenId, _unitPrice());
        _withdraw(tokenId, _holdings(tokenId).totalShares);
    }

    function _withdraw(
        uint tokenId,
        uint amount
    ) internal noWithdrawInProgress noBridgeInProgress {
        require(msg.sender == _ownerOf(tokenId), 'not owner');

        VaultParentStorage.Layout storage l = VaultParentStorage.layout();

        l.withdrawsInProgress = l.childChains.length;
        uint portion = (amount * 10 ** 18) / _totalShares();
        uint currentUnitPrice;

        // I don't really like smuggling this logic in here at this level
        // But it means that if a manager isn't charging a performanceFee then we don't need to call unitPrice()
        // Which means we don't need to sync.
        if (
            (_holdings(tokenId).performanceFee == 0 &&
                _managerPerformanceFee() == 0) || isSystemToken(tokenId)
        ) {
            currentUnitPrice = 0;
        } else {
            currentUnitPrice = _unitPrice();
        }
        _burnShares(tokenId, amount, currentUnitPrice);
        _withdraw(msg.sender, portion);
        _sendWithdrawRequestsToChildren(msg.sender, portion);
    }

    ///
    /// Cross Chain Requests
    ///

    // In reality this would be protected and only callable if there
    // is a deposit/withdraw queued.

    function requestTotalValueUpdate() external payable {
        _requestTotalValueUpdate();
    }

    function _requestTotalValueUpdate() internal {
        VaultParentStorage.Layout storage l = VaultParentStorage.layout();
        (uint[] memory fees, uint totalFees) = _getSendQuoteMultiChain(
            this.requestTotalValueUpdate.selector,
            l.childChains
        );
        require(msg.value >= totalFees, 'insufficient fee');

        for (uint8 i = 0; i < l.childChains.length; i++) {
            uint16 siblingChainId = l.childChains[i];

            _registry().transport().sendValueUpdateRequest{ value: fees[i] }(
                ITransport.ValueUpdateRequest({
                    parentChainId: _registry().chainId(),
                    parentVault: address(this),
                    child: ITransport.ChildVault({
                        vault: l.children[siblingChainId],
                        chainId: siblingChainId
                    })
                })
            );
        }
    }

    function _sendWithdrawRequestsToChildren(
        address withdrawer,
        uint portion
    ) internal {
        VaultParentStorage.Layout storage l = VaultParentStorage.layout();
        (uint[] memory fees, uint totalFees) = _getSendQuoteMultiChain(
            this.withdraw.selector,
            l.childChains
        );
        require(msg.value >= totalFees, 'insufficient fee');
        for (uint8 i = 0; i < l.childChains.length; i++) {
            _sendWithdrawRequest(
                l.childChains[i],
                withdrawer,
                portion,
                fees[i]
            );
        }
    }

    function _sendWithdrawRequest(
        uint16 dstChainId,
        address withdrawer,
        uint portion,
        uint sendFee
    ) internal {
        VaultParentStorage.Layout storage l = VaultParentStorage.layout();

        _registry().transport().sendWithdrawRequest{ value: sendFee }(
            ITransport.WithdrawRequest({
                parentChainId: _registry().chainId(),
                parentVault: address(this),
                child: ITransport.ChildVault({
                    chainId: dstChainId,
                    vault: l.children[dstChainId]
                }),
                withdrawer: withdrawer,
                portion: portion
            })
        );
    }
}

