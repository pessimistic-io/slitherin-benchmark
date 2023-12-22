// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IERC20} from "./IERC20.sol";
import {IOracle} from "./IOracle.sol";
import {ISwapRouter} from "./ISwapRouter.sol";
import {IRouterUniV2} from "./IRouterUniV2.sol";
import {IBalancerVault} from "./IBalancerVault.sol";
import {Util} from "./Util.sol";
import {BytesLib} from "./BytesLib.sol";

interface IStrategyHelperVenue {
    function swap(address ast, bytes calldata path, uint256 amt, uint256 min, address to) external;
}

contract StrategyHelper is Util {
    error UnknownPath();
    error UnknownOracle();

    struct Path {
        address venue;
        bytes path;
    }

    mapping(address => address) public oracles;
    mapping(address => mapping(address => Path)) public paths;

    event SetOracle(address indexed ast, address indexed oracle);
    event SetPath(address indexed ast0, address indexed ast1, address venue, bytes path);

    constructor() {
        exec[msg.sender] = true;
    }

    function setOracle(address ast, address oracle) external auth {
        oracles[ast] = oracle;
        emit SetOracle(ast, oracle);
    }

    function setPath(address ast0, address ast1, address venue, bytes calldata path) external auth {
        Path storage p = paths[ast0][ast1];
        p.venue = venue;
        p.path = path;
        emit SetPath(ast0, ast1, venue, path);
    }

    function price(address ast) public view returns (uint256) {
        IOracle oracle = IOracle(oracles[ast]);
        if (address(oracle) == address(0)) revert UnknownOracle();
        return uint256(oracle.latestAnswer()) * 1e18 / (10 ** oracle.decimals());
    }

    function value(address ast, uint256 amt) public view returns (uint256) {
        return amt * price(ast) / (10 ** IERC20(ast).decimals());
    }

    function convert(address ast0, address ast1, uint256 amt) public view returns (uint256) {
        return value(ast0, amt) * (10 ** IERC20(ast1).decimals()) / price(ast1);
    }

    function swap(address ast0, address ast1, uint256 amt, uint256 slp, address to) external returns (uint256) {
        if (amt == 0) return 0;
        if (ast0 == ast1) {
          if (!IERC20(ast0).transferFrom(msg.sender, to, amt)) revert TransferFailed();
          return amt;
        }
        Path memory path = paths[ast0][ast1];
        if (path.venue == address(0)) revert UnknownPath();
        if (!IERC20(ast0).transferFrom(msg.sender, path.venue, amt)) revert TransferFailed();
        uint256 min = convert(ast0, ast1, amt) * (10000 - slp) / 10000;
        uint256 before = IERC20(ast1).balanceOf(to);
        IStrategyHelperVenue(path.venue).swap(ast0, path.path, amt, min, to);
        return IERC20(ast1).balanceOf(to) - before;
    }
}

contract StrategyHelperUniswapV2 {
    IRouterUniV2 router;

    constructor(address _router) {
        router = IRouterUniV2(_router);
    }

    function swap(address ast, bytes calldata path, uint256 amt, uint256 min, address to) external {
        IERC20(ast).approve(address(router), amt);
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amt,
            min, 
            parsePath(path),
            to,
            type(uint256).max
        );
    }

    function parsePath(bytes memory path) internal pure returns (address[] memory) {
        uint256 size = path.length / 20;
        address[] memory p = new address[](size);
        for (uint256 i = 0; i < size; i++) {
            p[i] = address(uint160(bytes20(BytesLib.slice(path, i * 20, 20))));
        }
        return p;
    }
}

contract StrategyHelperUniswapV3 {
    ISwapRouter router;

    constructor(address _router) {
        router = ISwapRouter(_router);
    }

    function swap(address ast, bytes calldata path, uint256 amt, uint256 min, address to) external {
        IERC20(ast).approve(address(router), amt);
        router.exactInput(ISwapRouter.ExactInputParams({
            path: path,
            recipient: to,
            deadline: type(uint256).max,
            amountIn: amt,
            amountOutMinimum: min
        }));
    }
}

contract StrategyHelperBalancer {
    IBalancerVault vault;

    constructor(address _vault) {
        vault = IBalancerVault(_vault);
    }

    function swap(address ast, bytes calldata path, uint256 amt, uint256 min, address to) external {
        (address out, bytes32 poolId) = abi.decode(path, (address, bytes32));
        IERC20(ast).approve(address(vault), amt);
        vault.swap(
            IBalancerVault.SingleSwap({
                poolId: poolId,
                kind: 0,
                assetIn: ast,
                assetOut: out,
                amount: amt,
                userData: ""
            }),
            IBalancerVault.FundManagement({
                sender: address(this),
                fromInternalBalance: false,
                recipient: payable(to),
                toInternalBalance: false
            }),
            min,
            type(uint256).max
        );
    }
}

