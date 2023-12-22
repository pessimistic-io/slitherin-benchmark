// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "./IERC20.sol";

contract PrivateClaim {
  address public owner;
  uint256 public totalContributed;
  mapping(address => uint256) public coneAmount;
  mapping(address => uint256) public xConeAmount;

  address public coneAddress;
  address public xConeAddress;

  modifier onlyOwner() {
    require(msg.sender == owner, "Not the contract owner");
    _;
  }

  constructor(address _cone, address _xCone) {
    owner = msg.sender;
    coneAddress = _cone;
    xConeAddress = _xCone;
  }

  function contribute(
    address[] memory _contributor,
    uint256[] memory _coneAmount,
    uint256[] memory _xConeAmount
  ) public payable onlyOwner {
    require(_contributor.length == _coneAmount.length, "Array length mismatch");
    require(
      _contributor.length == _xConeAmount.length,
      "Array length mismatch"
    );
    for (uint256 i = 0; i < _contributor.length; i++) {
      require(_contributor[i] != address(0), "Invalid address");
      require(_coneAmount[i] > 0, "Invalid amount");
      require(_xConeAmount[i] > 0, "Invalid amount");
      coneAmount[_contributor[i]] = _coneAmount[i];
      xConeAmount[_contributor[i]] = _xConeAmount[i];
    }
  }

  function claim() external {
    require(coneAmount[msg.sender] > 0, "Nothing to claim");
    require(xConeAmount[msg.sender] > 0, "Nothing to claim");
    uint256 _coneAmount = coneAmount[msg.sender];
    uint256 _xConeAmount = xConeAmount[msg.sender];
    coneAmount[msg.sender] = 0;
    xConeAmount[msg.sender] = 0;
    IERC20(coneAddress).transfer(msg.sender, _coneAmount);
    IERC20(xConeAddress).transfer(msg.sender, _xConeAmount);
  }
}

