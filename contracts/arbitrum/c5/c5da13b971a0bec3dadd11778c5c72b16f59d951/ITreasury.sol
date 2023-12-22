// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

interface ITreasury {
    function manage( address _token, uint _amount ) external;
    function deposit( uint _amount, address _token, uint _profit ) external returns ( bool );
    function valueOf( address _token, uint _amount ) external view returns ( uint value_ );
}
