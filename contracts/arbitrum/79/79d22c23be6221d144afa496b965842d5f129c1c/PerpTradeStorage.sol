// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Errors} from "./Errors.sol";
import {GmxStorage} from "./GmxStorage.sol";
import {CapStorage} from "./CapStorage.sol";
import {KwentaStorage} from "./KwentaStorage.sol";
import {IOperator} from "./IOperator.sol";
import {DS} from "./IDataStore.sol";

contract PerpTradeStorage is GmxStorage, CapStorage, KwentaStorage {
    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    enum Order {
        UPDATE_INCREASE,
        UPDATE_DECREASE,
        CANCEL_INCREASE,
        CANCEL_DECREASE,
        CANCEL_MULTIPLE
    }

    struct Rewards {
        address ARB; // token
        address REWARDS;
        address KWENTA; // token
        address OP; // token
        address BATCHCLAIM;
        address REWARDESCROW;
    }

    address public operator;
    address public CROSS_CHAIN_ROUTER;
    Rewards public rewards;

    /*//////////////////////////////////////////////////////////////
                              EVENTS
    //////////////////////////////////////////////////////////////*/

    event InitPerpTrade(address indexed operator);
    event GmxUpdate(Gmx dex);
    event CapUpdate(address indexed ds);
    event KwentaUpdate(address indexed kwentaFactory, address indexed susd);
    event CrossChainUpdate(address indexed router);
    event RewardsUpdate(Rewards rewards);

    /*//////////////////////////////////////////////////////////////
                        CONSTRUCTOR/MODIFIERS
    //////////////////////////////////////////////////////////////*/

    constructor(address _operator) {
        operator = _operator;
        emit InitPerpTrade(_operator);
    }

    modifier onlyOwner() {
        address owner = IOperator(operator).getAddress("OWNER");
        if (msg.sender != owner) revert Errors.NotOwner();
        _;
    }

    modifier onlyQorVault() {
        address q = IOperator(operator).getAddress("Q");
        address vault = IOperator(operator).getAddress("VAULT");
        if ((msg.sender != q) && (msg.sender != vault)) revert Errors.NoAccess();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                             SETTERS
    //////////////////////////////////////////////////////////////*/

    /// @notice function to set/update the necessary contract addresses of gmx
    /// @dev can only be called by the owner
    /// @param _dex `Gmx` struct which contains the necessary contract addresses of GMX
    function setGmx(Gmx memory _dex) external onlyOwner {
        dex = _dex;
        emit GmxUpdate(_dex);
    }

    /// @notice function to set/update the necessary contract addresses of cap
    /// @dev can only be called by the owner
    /// @param _ds address of the DS contract
    function setCap(address _ds) external onlyOwner {
        ds = DS(_ds);
        MARKET_STORE = ds.getAddress("MarketStore");
        FUND_STORE = ds.getAddress("FundStore");
        ORDERS = ds.getAddress("Orders");
        PROCESSOR = ds.getAddress("Processor");
        ORDER_STORE = ds.getAddress("OrderStore");
        emit CapUpdate(_ds);
    }

    /// @notice function to set/update the necessary contract addresses of kwenta
    /// @dev can only be called by the owner
    /// @param _kwentaFactory address of kwenta factory contract
    /// @param _sUSD address of sUSD token
    function setKwenta(address _kwentaFactory, address _sUSD) external onlyOwner {
        kwentaFactory = _kwentaFactory;
        SUSD = _sUSD;
        emit KwentaUpdate(_kwentaFactory, _sUSD);
    }

    /// @notice function to set/update the necessary contract addresses of cross chain
    /// @dev can only be called by the owner
    /// @param _router address of the cross chain router
    function setCrossChainRouter(address _router) external onlyOwner {
        if (_router == address(0)) revert Errors.ZeroAddress();
        CROSS_CHAIN_ROUTER = _router;
        emit CrossChainUpdate(_router);
    }

    function setRewards(Rewards memory _rewards) external onlyOwner {
        rewards = _rewards;
        emit RewardsUpdate(_rewards);
    }
}

