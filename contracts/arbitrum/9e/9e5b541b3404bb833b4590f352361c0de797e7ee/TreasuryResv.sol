// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./SafeMath.sol";
import "./Address.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./Ownable.sol";
import "./IWETH.sol";



contract TreasuryResv is Ownable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using Address for address payable;


    mapping(string => address) public addDef;
    mapping(address => address) public elpToElpManager;
    mapping(address => address) public elpToElpTracker;


    receive() external payable {
        // require(msg.sender == weth, "invalid sender");
    }
    
    function setAddress(string[] memory _name_list, address[] memory _contract_list) external onlyOwner{
        for(uint i = 0; i < _contract_list.length; i++){
            addDef[_name_list[i]] = _contract_list[i];
        }
    }
    
    function withdrawToken(address _token, uint256 _amount, address _dest) external onlyOwner {
        IERC20(_token).safeTransfer(_dest, _amount);
    }

    function depositNative(uint256 _amount) external payable onlyOwner {
        uint256 _curBalance = address(this).balance;
        IWETH(addDef["nativeToken"]).deposit{value: _amount > _curBalance ? _curBalance : _amount}();
    }
}
