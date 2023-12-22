// SPDX-License-Identifier: MIT

pragma solidity >0.8.0;

interface IBirdFundsHolder {
    function holdFunds(string memory _FundName, address _Token, address _Receiver, uint256 _TokenAmount, uint256 _ReleaseTime) external;
    function releaseFunds(uint256 fundNo) external;
}

