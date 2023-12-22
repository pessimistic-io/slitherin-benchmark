// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "./Strategy.sol";

contract Strategy_Arx is Strategy {
    using SafeERC20 for IERC20;

    address[] public earned2ToEarnedPath;

    constructor(
        address[] memory _addresses,
        address[] memory _tokenAddresses,
        bool _isSingleVault,
        bool _isAutoComp,
        uint256 _pid,
        address[] memory _earnedToToken0Path,
        address[] memory _earnedToToken1Path,
        address[] memory _earned2ToEarnedPath,
        uint256 _withdrawFeeFactor
    ) public {
        vault = _addresses[0];
        farmContractAddress = _addresses[1];
        govAddress = _addresses[2];
        uniRouterAddress = _addresses[3];

        wftmAddress = _tokenAddresses[0];
        wantAddress = _tokenAddresses[1];
        earnedAddress = _tokenAddresses[2];
        token0Address = _tokenAddresses[3];
        token1Address = _tokenAddresses[4];

        pid = _pid;
        isSingleVault = _isSingleVault;
        isAutoComp = _isAutoComp;

        earnedToToken0Path = _earnedToToken0Path;
        earnedToToken1Path = _earnedToToken1Path;
        earned2ToEarnedPath = _earned2ToEarnedPath;

        // Reverse path
        for (uint256 i = earnedToToken0Path.length; i > 0; i--) {
            token0ToEarnedPath.push(earnedToToken0Path[i - 1]);
        }
        for (uint256 i = earnedToToken1Path.length; i > 0; i--) {
            token1ToEarnedPath.push(earnedToToken1Path[i - 1]);
        }

        withdrawFeeFactor = _withdrawFeeFactor;
    }

    function _harvest() internal override {
        _unfarm(0);

        address earned2Address = earned2ToEarnedPath[0];
        uint256 earned2Amt = IERC20(earned2Address).balanceOf(address(this));

        if (earned2Amt > 0) {
            IERC20(earned2Address).safeIncreaseAllowance(
                uniRouterAddress,
                earned2Amt
            );

            _safeSwap(
                uniRouterAddress,
                earned2Amt,
                slippageFactor,
                earned2ToEarnedPath,
                address(this),
                block.timestamp + routerDeadlineDuration
            );
        }
    }

}
