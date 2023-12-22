// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {Util} from "./Util.sol";
import {IERC20} from "./IERC20.sol";
import {IOracle} from "./IOracle.sol";

interface IFixedStrikeOptionTeller {
    function getOptionToken(
        address payoutToken,
        address quoteToken,
        uint48 eligible,
        uint48 expiry,
        address receiver,
        bool call,
        uint256 strikePrice
    ) external view returns (address);
    function deploy(
        address payoutToken,
        address quoteToken,
        uint48 eligible,
        uint48 expiry,
        address receiver,
        bool call,
        uint256 strikePrice
    ) external returns (address);
    function create(address optionToken, uint256 amount) external;
    function exercise(address optionToken, uint256 amount) external;
}


contract LiquidityMiningPluginOrdo is Util {
    IFixedStrikeOptionTeller public teller;
    IOracle public oracle;
    address public multisig;
    address public usdc;
    uint256 public bonus = 0.1e18;
    uint256 public discount = 0.5e18;
    mapping(uint256 => address) options;

    event File(bytes32 indexed, address);
    event File(bytes32 indexed, uint256);

    error NoBonusTokensLeft();

    constructor(address _teller, address _oracle, address _multisig, address _usdc) {
        exec[msg.sender] = true;
        teller = IFixedStrikeOptionTeller(_teller);
        oracle = IOracle(_oracle);
        multisig = _multisig;
        usdc = _usdc;
    }

    function file(bytes32 what, address data) external auth {
        if (what == "exec") exec[data] = !exec[data];
        emit File(what, data);
    }

    function file(bytes32 what, uint256 data) external auth {
        if (what == "paused") paused = data == 1;
        if (what == "bonus") bonus = data;
        if (what == "discount") discount = data;
        emit File(what, data);
    }

    function onHarvest(address to, address token, uint256 amount) external live auth {
        uint256 price = uint256(oracle.latestAnswer()) * 1e6 / (10 ** oracle.decimals());
        uint256 strike = price * (1e18 - discount) / 1e18 / 0.01e6 * 0.01e6;
        uint256 amountWithBonus = amount * (1e18 + bonus) / discount;
        if (IERC20(token).balanceOf(address(this)) < amountWithBonus) {
            revert NoBonusTokensLeft();
        }
        address option = options[strike];
        if (option == address(0)) {
            option = teller.deploy(
                token,
                usdc,
                0, // now
                2521843200,
                multisig,
                true,
                strike
            );
            options[strike] = option;
        }
        IERC20(token).approve(address(teller), amountWithBonus);
        teller.create(option, amountWithBonus);
        push(IERC20(option), to, amountWithBonus);
    }

    function rescueToken(address token, uint256 amount) external auth {
        push(IERC20(token), msg.sender, amount);
    }

    function getBalances(address owner, uint256 start, uint256 size) external view returns (address[] memory tokens, uint256[] memory strikes, uint256[] memory balances) {
        tokens = new address[](size);
        strikes = new uint256[](size);
        balances = new uint256[](size);
        for (uint256 i = 0; i < size; i++) {
            uint256 strike = start + (i * 0.01e6);
            tokens[i] = options[strike];
            strikes[i] = strike;
            if (tokens[i] != address(0)) {
                balances[i] = IERC20(tokens[i]).balanceOf(owner);
            }
        }
    }
}

