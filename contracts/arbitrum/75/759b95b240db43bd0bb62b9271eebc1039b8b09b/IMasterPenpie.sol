// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.17;

interface IMasterPenpie {
    function multiclaimSpecPNP(address[] memory _stakingTokens, address[][] memory _rewardTokens, bool _withPNP) external;
}
