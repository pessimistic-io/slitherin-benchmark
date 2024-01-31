// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.7;

import "./ICapacitorFactory.sol";
import "./SingleCapacitor.sol";
import "./HashChainCapacitor.sol";
import "./SingleDecapacitor.sol";
import "./HashChainDecapacitor.sol";
import "./RescueFundsLib.sol";
import "./Ownable.sol";

contract CapacitorFactory is ICapacitorFactory, Ownable(msg.sender) {
    function deploy(
        uint256 capacitorType_,
        uint256 /** siblingChainSlug */
    ) external override returns (ICapacitor, IDecapacitor) {
        if (capacitorType_ == 1) {
            return (new SingleCapacitor(msg.sender), new SingleDecapacitor());
        }
        if (capacitorType_ == 2) {
            return (
                new HashChainCapacitor(msg.sender),
                new HashChainDecapacitor()
            );
        }
        revert InvalidCapacitorType();
    }

    function rescueFunds(
        address token_,
        address userAddress_,
        uint256 amount_
    ) external onlyOwner {
        RescueFundsLib.rescueFunds(token_, userAddress_, amount_);
    }
}

