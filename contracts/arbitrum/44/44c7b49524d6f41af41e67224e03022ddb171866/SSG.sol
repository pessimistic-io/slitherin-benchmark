// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./SafeMath.sol";
import "./ERC20Burnable.sol";

import "./Operator.sol";

contract SSG is ERC20Burnable, Operator {
    using SafeMath for uint256;

    uint256 public constant FARMING_SHARE = 55349 ether;
    uint256 public constant LIQUIDITY_SHARE = 10000 ether;
    uint256 public constant TEAM_SHARE = 5534 ether;
    uint256 public constant PRESALE_SHARE = 39814 ether;

    bool public tokenDistributed = false;

    constructor() ERC20("Sausages", "SSG") {
        _mint(msg.sender, 1 ether);
    }

    function distributeTokens(address _ssgPool, address _liquidityReceiver, address _teamReceiver, address _presaleReceiver) onlyOperator external {
        require(!tokenDistributed, "only can distribute once");

        require(_ssgPool != address(0), "!_ssgPool");
        require(_liquidityReceiver != address(0), "!_liquidityReceiver");
        require(_teamReceiver != address(0), "!_teamReceiver");
        require(_presaleReceiver != address(0), "!_presaleReceiver");

        tokenDistributed = true;

        _mint(_ssgPool, FARMING_SHARE);
        _mint(_liquidityReceiver, LIQUIDITY_SHARE);
        _mint(_teamReceiver, TEAM_SHARE);
        _mint(_presaleReceiver, PRESALE_SHARE);
    }

    function burn(uint256 amount) public override {
        super.burn(amount);
    }

    function governanceRecoverUnsupported(IERC20 _token, uint256 _amount, address _to) onlyOperator external {
        _token.transfer(_to, _amount);
    }
}

