// SPDX-License-Identifier: Ridotto Core License

/*
.------..------..------..------..------..------.     .------..------..------.
|G.--. ||L.--. ||O.--. ||B.--. ||A.--. ||L.--. |.-.  |R.--. ||N.--. ||G.--. |
| :/\: || :/\: || :/\: || :(): || (\/) || :/\: ((5)) | :(): || :(): || :/\: |
| :\/: || (__) || :\/: || ()() || :\/: || (__) |'-.-.| ()() || ()() || :\/: |
| '--'G|| '--'L|| '--'O|| '--'B|| '--'A|| '--'L| ((1)) '--'R|| '--'N|| '--'G|
`------'`------'`------'`------'`------'`------'  '-'`------'`------'`------'
*/

pragma solidity ^0.8.9;

// Randomizer protocol interface
interface IRandomizer {
    function request(uint256 callbackGasLimit) external returns (uint256);

    function request(uint256 callbackGasLimit, uint256 confirmations) external returns (uint256);

    function clientWithdrawTo(address _to, uint256 _amount) external;
}

