// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ERC20Burnable.sol";
import "./Math.sol";
import "./SafeMath.sol";

import "./Operator.sol";
import "./SafeMath8.sol";

contract BBQToken is ERC20Burnable, Operator {
    using SafeMath for uint256;

    uint256 public constant INITIAL_BBQ_LIQUIDITY = 20000 ether;
    uint256 public constant INITIAL_BBQ_PRESALE = 79628 ether;
    uint256 public constant INITIAL_BBQ_TEAM = 14232 ether;
    uint256 public constant INITIAL_BBQ_TREASURY = 28465 ether;

    bool public tokenDistributed = false;

    constructor() ERC20("BBQ Party", "BBQ") {
        _mint(msg.sender, 1 ether);
    }

    /**
     * @notice Operator mints BBQ to a recipient
     * @param recipient_ The address of recipient
     * @param amount_ The amount of BBQ to mint to
     * @return whether the process has been done
     */
    function mint(address recipient_, uint256 amount_) public onlyOperator returns (bool) {
        uint256 balanceBefore = balanceOf(recipient_);
        _mint(recipient_, amount_);
        uint256 balanceAfter = balanceOf(recipient_);

        return balanceAfter > balanceBefore;
    }

    function burn(uint256 amount) public override {
        super.burn(amount);
    }

    function burnFrom(address account, uint256 amount) public onlyOperator override {
        super.burnFrom(account, amount);
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, _msgSender(), allowance(sender, _msgSender()).sub(amount, "ERC20: transfer amount exceeds allowance"));
        return true;
    }

    function distributeTokens(address _liquidityReceiver, address _presaleReceiver, address _teamReceiver, address _treasury) onlyOperator external {
        require(!tokenDistributed, "only can distribute once");

        require(_liquidityReceiver != address(0), "!_liquidityReceiver");
        require(_presaleReceiver != address(0), "!_presaleReceiver");
        require(_teamReceiver != address(0), "!_teamReceiver");
        require(_treasury != address(0), "!_treasury");

        tokenDistributed = true;

        _mint(_liquidityReceiver, INITIAL_BBQ_LIQUIDITY);
        _mint(_presaleReceiver, INITIAL_BBQ_PRESALE);
        _mint(_teamReceiver, INITIAL_BBQ_TEAM);
        _mint(_treasury, INITIAL_BBQ_TREASURY);
    }

    function governanceRecoverUnsupported(IERC20 _token, uint256 _amount, address _to) onlyOperator external {
        _token.transfer(_to, _amount);
    }
}

