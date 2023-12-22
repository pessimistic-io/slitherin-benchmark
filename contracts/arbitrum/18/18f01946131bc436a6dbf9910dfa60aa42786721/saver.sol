// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import {Ownable} from "./Ownable.sol";
import {IERC20} from "./IERC20.sol";

interface IFarm {
    function balanceOf(address account) external view returns (uint256);
}

interface IWithdrawer {
    function withdraw(uint256 _pid, uint256 _amount) external;
}

interface IRouter {
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB);

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}

contract Saver is Ownable {
    IFarm public yw_farm = IFarm(0x4A9D4B2F9b9f8ac0de2e6A1ef53c2374fD0520c5);
    IWithdrawer public yw_withdrawer =
        IWithdrawer(0x8fEc7A778Cba11a98f783Ebe9826bEc3b5E67F95);
    IRouter public lp_router =
        IRouter(0xcDAeC65495Fa5c0545c5a405224214e3594f30d8);
    IERC20 public lp_pool = IERC20(0x8363e4a09D9998061d2F7244422627695e24FD15);
    IERC20 public weth = IERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    IERC20 public aeth = IERC20(0x8F4581D173FFD2c439824465366a67c509A813ac);

    constructor() Ownable() {}

    function save() public {
        (bool need_to_save, ) = checkNeedToSave();
        require(need_to_save || msg.sender == owner(), "No need to save");
        yw_withdrawer.withdraw(62, yw_farm.balanceOf(address(this)));

        uint256 balance_of_lp = lp_pool.balanceOf(address(this));
        lp_pool.approve(address(lp_router), balance_of_lp);
        lp_router.removeLiquidity(
            address(weth),
            address(aeth),
            balance_of_lp,
            0,
            0,
            address(this),
            block.timestamp
        );

        uint256 balance_of_aeth = aeth.balanceOf(address(this));
        aeth.approve(address(lp_router), balance_of_aeth);
        address[] memory path = new address[](2);
        path[0] = address(aeth);
        path[1] = address(weth);
        lp_router.swapExactTokensForTokens(
            balance_of_aeth,
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    function checkNeedToSave() public view returns (bool, bytes memory) {
        uint256 balance_of_weth = weth.balanceOf(address(lp_pool));
        uint256 balance_of_aeth = aeth.balanceOf(address(lp_pool));

        if (balance_of_weth * 10 < balance_of_aeth * 9) {
            return (true, new bytes(0));
        } else {
            return (false, new bytes(0));
        }
    }

    function deposit(uint256 _amount, address _token) public onlyOwner {
        IERC20 token = IERC20(_token);
        require(token.balanceOf(msg.sender) >= _amount, "Not enough balance");
        token.transferFrom(msg.sender, address(this), _amount);
    }

    function withdraw(uint256 _amount, address _token) public onlyOwner {
        IERC20 token = IERC20(_token);
        require(
            token.balanceOf(address(this)) >= _amount,
            "Not enough balance"
        );
        token.transfer(msg.sender, _amount);
    }
}

