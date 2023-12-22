// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.23;

import "./IThetaVault.sol";

interface IMegaThetaVaultManagement {

	event FulfillerSet(address newFulfiller);
	event DepositorSet(address newDepositor);
	event MinAmountsSet(uint256 newMinDepositAmount, uint256 newMinWithdrawAmount);
	event DepositCapSet(uint256 newDepositCap);
	event MinRebalanceDiffSet(uint256 newMinRebalanceDiff);

    function rebalance(uint16 cviThetaVaultPercentage) external;

    function setFulfiller(address newFulfiller) external;
    function setDepositor(address newDepositor) external;
    function setDepositCap(uint256 newDepositCap) external;
    function setMinRebalanceDiff(uint256 newMinRebalanceDiff) external;
}

