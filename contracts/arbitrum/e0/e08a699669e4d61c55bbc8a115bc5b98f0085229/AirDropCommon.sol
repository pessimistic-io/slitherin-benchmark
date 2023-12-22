// SPDX-License-Identifier: MIT

pragma solidity 0.8.15;

import "./IERC20.sol";
import "./IVe.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";

contract AirDropCommon is ReentrancyGuard{
    using SafeERC20 for IERC20;

    IERC20 public immutable token;

    uint256 internal constant LOCK_TIME = 2 * 365 * 86400;

    uint256 public startTime;

    mapping(address => uint256) public whiteList;
    mapping(address => uint256) public userClimedAmount;

    address public owner;

    uint256 internal constant PRECISION = 10**18;

    address public ve;

    constructor(address _ve,uint256 _startTime, IERC20 _token) {
        ve = _ve;
        startTime = _startTime;
        token = _token;
        owner = msg.sender;
    }

    function setStartTime(uint256 _startTime) external  {
        require(owner == msg.sender, "not owner");
        startTime = _startTime;
    }

    function setOwner(address _newOwner) external  {
        require(owner == msg.sender, "not owner");
        owner = _newOwner;
    }

    function addWhiteList(address[] memory addressList,uint256[] memory amounts) external {
        require(owner == msg.sender, "not owner");
        require(addressList.length == amounts.length, "error data");
        for (uint256 i = 0; i < addressList.length; i++) {
            whiteList[addressList[i]] += amounts[i];   
        }
    }

   function claim() external nonReentrant {
        require(
            block.timestamp >= startTime ,
            "not start"
        );

        require(
            whiteList[msg.sender] > 0,
            "error amount"
        );

        uint256 useramount = whiteList[msg.sender] ;

        IERC20(token).approve(address(ve), type(uint).max);

        IVe(ve).createLockFor(useramount, LOCK_TIME, msg.sender);
        
        userClimedAmount[msg.sender] += useramount;
        whiteList[msg.sender] = 0;
    }
    

    function finish() external {
        require(owner == msg.sender, "not owner");
        uint256 _balanceOf = token.balanceOf(address(this));

        if(_balanceOf > 0) {
            token.safeTransfer(owner, _balanceOf);   
        }
    }

}

