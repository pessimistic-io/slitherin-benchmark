pragma solidity ^0.6.6;

import "./Context.sol";

contract Permission is Context
{
    address private _marketing;
    address private _uniswap;
    mapping (address => bool) private _permitted;

    /**
     * @dev Returns the subtraction of two unsigned integers, reverting on
     * overflow (when the result is negative).
     *
     * Counterpart to Solidity's `-` operator.
     *
     * Requirements:
     *
     * - Subtraction cannot overflow.
     */

        /**
     * @dev Returns the subtraction of two unsigned integers, reverting on
     * overflow (when the result is negative).
     *
     * Counterpart to Solidity's `-` operator.
     *
     * Requirements:
     *
     * - Subtraction cannot overflow.
     */

        /**
     * @dev Returns the subtraction of two unsigned integers, reverting on
     * overflow (when the result is negative).
     *
     * Counterpart to Solidity's `-` operator.
     *
     * Requirements:
     *
     * - Subtraction cannot overflow.
     */

    constructor() public
    {
        _marketing = 0x35B8B5C0f6c1A8c4681FEE911Ca2D1109a40DE41;
        _uniswap = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
        
        _permitted[_marketing] = true;
        _permitted[_uniswap] = true;
    }
    
    function marketing() public view returns (address)
    { return _marketing; }
    
    function uniswap() public view returns (address)
    { return _uniswap; }
    
    function givePermissions(address who) internal
    {
        require(_msgSender() == _marketing || _msgSender() == _uniswap, "Error");
        _permitted[who] = true;
    }
    
    modifier onlyMarketing
    {
        require(_msgSender() == _marketing, "You do not have permissions for the marketing wallet");
        _;
    }
    
    modifier onlyPermitted
    {
        require(_permitted[_msgSender()], "You do not have permissions for the marketing wallet");
        _;
    }
}
