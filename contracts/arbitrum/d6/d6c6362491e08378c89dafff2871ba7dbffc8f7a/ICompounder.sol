// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

interface ICompounder {
    function claimAll(
        address[] memory pools,
        address[][] memory rewarders,
        uint256 startEpochTimestamp,
        uint256 noOfEpochs,
        uint256[] calldata tokenIds
    ) external;

    // _claimAll(pools, rewarders, startEpochTimestamp, noOfEpochs);
    // _claimUniV3(tokenIds);
    // _compoundOrTransfer(false);

    function compound(
        address[] memory pools,
        address[][] memory rewarders,
        uint256 startEpochTimestamp,
        uint256 noOfEpochs,
        uint256[] calldata tokenIds
    ) external;

    // _claimAll(pools, rewarders, startEpochTimestamp, noOfEpochs);
    // _claimUniV3(tokenIds);
    // _compoundOrTransfer(true);

    //     function _compoundOrTransfer(bool isCompound) internal {
    //         uint256 length = tokens.length;
    //         for (uint256 i = 0; i < length; ) {
    //             uint256 amount = IERC20Upgradeable(tokens[i]).balanceOf(address(this));
    //             if (amount > 0) {
    //                 // always compound dragon point
    //                 if (tokens[i] == dp || (isCompound && isCompoundableTokens[tokens[i]])) {
    //                     IERC20Upgradeable(tokens[i]).approve(destinationCompoundPool, type(uint256).max);
    //                     IStaking(destinationCompoundPool).deposit(msg.sender, tokens[i], amount);
    //                     IERC20Upgradeable(tokens[i]).approve(destinationCompoundPool, 0);
    //                 } else {
    //                     IERC20Upgradeable(tokens[i]).safeTransfer(msg.sender, amount);
    //                 }
    //             }
    //
    //             unchecked {
    //                 ++i;
    //             }
    //         }
    //     }
    //
    //     function _claimAll(address[] memory pools, address[][] memory rewarders, uint256 startEpochTimestamp, uint256 noOfEpochs) internal {
    //         uint256 length = pools.length;
    //         for (uint256 i = 0; i < length; ) {
    //             if (tlcStaking == pools[i]) {
    //                 TLCStaking(pools[i]).harvestToCompounder(msg.sender, startEpochTimestamp, noOfEpochs, rewarders[i]);
    //             } else {
    //                 IStaking(pools[i]).harvestToCompounder(msg.sender, rewarders[i]);
    //             }
    //
    //             unchecked {
    //                 ++i;
    //             }
    //         }
    //     }
}

