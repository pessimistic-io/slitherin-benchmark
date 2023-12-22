// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "./OwnableUpgradeable.sol";
import "./SafeMath.sol";
import "./SafeERC20.sol";

contract QuoMinter is OwnableUpgradeable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    address public quo;

    uint256 public constant FACTOR_DENOMINATOR = 10000;
    uint256 public factor;

    mapping(address => bool) public access;

    event AccessUpdated(address _operator, bool _access);
    event Minted(address indexed _to, uint256 _amount);

    function initialize(address _quo) public initializer {
        __Ownable_init();

        quo = _quo;
        factor = FACTOR_DENOMINATOR;
    }

    function setFactor(uint256 _factor) external onlyOwner {
        factor = _factor;
    }

    function setAccess(address _operator, bool _access) external onlyOwner {
        require(_operator != address(0), "invalid _operator!");
        access[_operator] = _access;

        emit AccessUpdated(_operator, _access);
    }

    function mint(address _to, uint256 _amount) external {
        require(access[msg.sender], "!auth");

        uint256 mintAmount = _amount.mul(factor).div(FACTOR_DENOMINATOR);
        require(
            IERC20(quo).balanceOf(address(this)) >= mintAmount,
            "insufficient balance"
        );
        IERC20(quo).safeTransfer(_to, mintAmount);

        emit Minted(_to, mintAmount);
    }
}

