// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC20_IERC20.sol";
import "./ERC20.sol";
import "./Ownable.sol";
import "./SafeMath.sol";
import "./SafeERC20.sol";

import "./IUniswapFactory.sol";
import "./IUniswapRouter.sol";
import "./IERC20Mintable.sol";
import "./IGalaxyStable.sol";

contract FairLaunch is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using SafeERC20 for IERC20Mintbale;
    using SafeERC20 for IGalaxyStable;

    uint256 private constant MIN_AMOUNT = 10e10;
    uint256 private constant MAX_AMOUNT = 5e18;

    uint256 private constant TOTAL_AMOUNT = 202e18;

    IUniswapRouter private constant router =
        IUniswapRouter(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506);

    IUniswapFactory private constant factory =
        IUniswapFactory(0xc35DADB65012eC5796536bD9864eD8773aBc74C4);

    IGalaxyStable public galaxy;
    IERC20Mintbale public galaxyfounder;

    bool public withdrawal;
    uint256 public claimTime;
    uint256 public totalBalance;

    mapping(address => uint256) public balances;

    event Enter(address indexed account, uint256 indexed amount);
    event Leave(address indexed account, uint256 indexed amount);

    constructor(address _gsaddress, address _gfaddress) {
        galaxy = IGalaxyStable(_gsaddress);
        galaxyfounder = IERC20Mintbale(_gfaddress);
    }

    function lp() public view returns (address) {
        return factory.getPair(address(galaxy), router.WETH());
    }

    function totalLpBalance() public view returns (uint256) {
        address pair = lp();
        if (pair == address(0)) return 0;
        return IERC20(pair).balanceOf(address(this));
    }

    function claimable(address account) public view returns (uint256) {
        if (totalLpBalance() == 0) return 0;

        return balances[account].mul(totalLpBalance()).div(totalBalance);
    }

    function enter() external payable {
        require(msg.value >= MIN_AMOUNT, "min limit");
        require(balances[msg.sender] + msg.value <= MAX_AMOUNT, "max limit");

        galaxyfounder.mint(msg.value, msg.sender);

        galaxy.mint(msg.value * 1300, address(this));

        totalBalance = totalBalance.add(msg.value);
        balances[msg.sender] = balances[msg.sender].add(msg.value);

        emit Enter(msg.sender, msg.value);
    }

    function leave() external {
        if (withdrawal) {
            payable(msg.sender).transfer(balances[msg.sender]);
        } else {
            require(block.timestamp > claimTime && claimTime > 0, "locked");

            uint256 amount = claimable(msg.sender);
            if (amount > 0) {
                uint256 bal = IERC20(lp()).balanceOf(address(this));
                if (bal < amount) {
                    IERC20(lp()).transfer(msg.sender, bal);
                } else {
                    IERC20(lp()).transfer(msg.sender, amount);
                }

                emit Leave(msg.sender, amount);
            }
        }
    }

    function initial() external onlyOwner {
        address dead = 0x000000000000000000000000000000000000dEaD;

        galaxy.safeApprove(address(router), 0);
        galaxy.safeApprove(address(router), totalBalance);

        router.addLiquidityETH{value: totalBalance}(
            address(galaxy),
            totalBalance,
            0,
            0,
            address(this),
            block.timestamp
        );

        // distribute 30% to black hole
        uint256 burnAmount = totalLpBalance().mul(30).div(100);
        IERC20(lp()).transfer(dead, burnAmount);

        uint256 remain = galaxy.balanceOf(address(this));
        galaxy.transfer(dead, remain);

        claimTime = block.timestamp;
    }

    function emergencyWithDraw(address _tokenAddress, uint amount)
        public
        onlyOwner
    {
        IERC20 token = IERC20(_tokenAddress);
        token.approve(address(this), amount);
        token.transferFrom(address(this), msg.sender, amount);
    }

    function withFees() public onlyOwner {
        payable(msg.sender).transfer(address(this).balance);
    }

    function setDynamicFee(uint _dynamicFee) public onlyOwner {
        galaxy.setDynamicFee(_dynamicFee);
    }

    function setTheasuryAddress(address _address) public onlyOwner {
        galaxy.setTheasuryAddress(_address);
    }

    function setEmergencySituation(bool _val) external onlyOwner {
        withdrawal = _val;
    }
}

