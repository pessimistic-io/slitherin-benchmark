// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./ERC20Upgradeable.sol";
import "./ERC20BurnableUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./Initializable.sol";

interface IStrategOperatingPaymentToken {
    event OperationApproval(address indexed owner, address indexed spender, uint256 value);
    event OperationPayment(address indexed from, address indexed to, uint256 value);
    event TreasuryChanged(address treasury);
    event OperatorProxyChanged(address to);
    event PaymentFeeChanged(uint256 to);

    error NotOperator();
    error NotTreasury();
    error InsufficientPaymentAllowance();
    error PaymentExceedsBalance();
    error NoMsgValue();
    error NoBurnValue();

    function getSponsors(address _spender) external view returns (address[] memory, uint256[] memory);
    function weth() external view returns (address);
    function mint() external payable;
    function mint(address to) external payable;
    function burn(uint256 _amount) external;
    function burn(address _to, uint256 _amount) external;
    function approveOperation(address spender, uint256 amount) external returns (bool);
    function executePayment(address _for, address _operator, uint256 _amount) external returns (bool);
    function executePaymentFrom(address _payer, address _for, address _operator, uint256 _amount)
        external
        returns (bool);
    function setOperatorProxy(address _operatorProxy) external;
    function setPaymentFee(uint256 _paymentFee) external;
    function operationAllowances(address owner, address spender) external view returns (uint256);
}

