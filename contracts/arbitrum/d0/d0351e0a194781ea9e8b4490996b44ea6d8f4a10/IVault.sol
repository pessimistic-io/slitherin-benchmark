// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface IVault {
    function withdraw(address _account, uint _amt, uint _total) external;
    function withdrawUSDT(address _account, uint _amt, uint _total) external;
    function pay(address _account, uint _amt) external;
    function payUSDT(address _account, uint _amt) external;
    function withdrawFee(uint _amt, uint _total) external;
    function withdrawFeeUSDT(uint _amt, uint _total) external;
    function referee(address _account) external view returns (address);
}

