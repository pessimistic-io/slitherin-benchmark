// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

interface ITreasury {
    function valueOf( address _token, uint _amount ) external view returns ( uint value_ );
    function mintRewards( address _recipient, uint _amount ) external;
    function deposit( uint _amount, address _token, uint _profit, address _referrer ) external returns ( uint value_ );
    function setPool(address _pool) external;
    function depositUniV3NFT(uint _tokenId, uint _profit) external returns ( uint send_ );
    function valueOfUniV3(uint _tokenId) external view returns ( uint value_ );
}
