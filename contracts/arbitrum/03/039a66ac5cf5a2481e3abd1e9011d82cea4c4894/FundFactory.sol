// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./OwnableUpgradeable.sol";

import "./ERC1967Proxy.sol";
import "./BeaconProxy.sol";
import "./console.sol";

import "./IInteraction.sol";
import "./IFundFactory.sol";
import "./IFees.sol";
import "./ITrade.sol";
import "./IRegistry.sol";

import "./InvestPeriod.sol";
import "./Upgradeable.sol";
import "./Token.sol";

contract FundFactory is Initializable, Upgradeable, IFundFactory {
    uint256 constant day = 24 * 60 * 60;
    uint256 public createFundFee;

    function initialize() public initializer {
        __Ownable_init();
        createFundFee = 0;
    }

    function setCreateFundFee(uint256 createFundFee_) external onlyOwner {
        createFundFee = createFundFee_;
    }

    function newFund(FundInfo calldata fundInfo) public override returns (uint256) {
        _checkIndent(fundInfo.indent, fundInfo.investPeriod);
        BeaconProxy trade = new BeaconProxy(registry.tradeBeacon(), new bytes(0));
        ITrade(address(trade)).initialize(
            msg.sender,
            fundInfo.whitelistMask,
            fundInfo.serviceMask,
            fundInfo.id
        );
        registry.interaction().newFund(
            fundInfo.id,
            fundInfo.hwm,
            fundInfo.investPeriod,
            msg.sender,
            new Token(fundInfo.id),
            address(trade),
            fundInfo.indent
        );
        _collectFees(fundInfo);
        emit FundCreated(
            msg.sender,
            fundInfo.id,
            fundInfo.hwm,
            fundInfo.subscriptionFee,
            fundInfo.performanceFee,
            fundInfo.managementFee,
            fundInfo.investPeriod,
            fundInfo.whitelistMask,
            fundInfo.serviceMask
        );
        return fundInfo.id;
    }

    function _collectFees(FundInfo calldata fundInfo) private {
        registry.fees().newFund(fundInfo.id, fundInfo.subscriptionFee, fundInfo.performanceFee, fundInfo.managementFee);
        registry.fees().gatherCf(fundInfo.id, msg.sender, createFundFee, address(registry.usdt()));
    }

    function _checkIndent(uint256 _indent, uint256 _investPeriod) private {
        uint maxIndent = day * (_investPeriod <= day * 7 && block.chainid != 420 ? 3 : 7);
        require(_indent <= maxIndent, "FF/ITS");
    }
}

