// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IERC20 } from "./IERC20.sol";
import "./TransferHelper.sol";
import "./Ownable.sol";
import "./Configure.sol";
import "./IAccountManager.sol";
import "./IAuthCenter.sol";
import "./IAccount.sol";
import "./IFundsProvider.sol";
import "./IOpManager.sol";
import "./FundsBasic.sol";

// import "hardhat/console.sol";

contract DexOperator is Ownable, FundsBasic {
    using TransferHelper for address;

    event CreateAccount(string id, address account);
    event DirectlyWithdraw(string id, string uniqueId, address token, uint256 amount);
    event SwapWithdraw(string id, string uniqueId, address srcToken, address dstToken, uint256 srcAmount, uint256 dstAmount);
    event Fee(string uniqueId, address feeTo, address token, uint256 amount);

    event UpdateOneInchRouter(address pre, address oneInchRouter);
    event SetOpManager(address preOpManager, address opManager);
    event SetAccountManager(address preAccountManager, address accountManager);
    event SetAuthCenter(address preAuthCenter, address authCenter);
    event SetFundsProvider(address preFundsProvider, address fundsProvider);
    event SetFeeTo(address preFeeTo, address feeTo);

    event Swap(
        string id,
        string uniqueId,
        uint8 assetFrom,
        uint8 action,
        address srcToken,
        address dstToken,
        address from,
        address to,
        address feeTo,
        uint256 srcTokenAmount,
        uint256 srcFeeAmount,
        uint256 returnAmount
    );

    address public opManager;
    address public accountManager;
    address public authCenter;
    address public fundsProvider;
    address public feeTo;
    address public oneInchRouter;
    // address oneInchRouter = 0x1111111254fb6c44bAC0beD2854e76F90643097d;

    bool flag;

    enum AssetFrom {
        FUNDSPROVIDER,
        ACCOUNT
    }

    enum Action {
        SWAP,
        PRECROSS
    }

    modifier onlyRunning() {
        bool running = IOpManager(opManager).isRunning(address(this));
        require(running, "BYDEFI: op paused!");
        _;
    }

    modifier onlyAccess() {
        IAuthCenter(authCenter).ensureOperatorAccess(_msgSender());
        _;
    }

    function init(
        address _opManager,
        address _accountManager,
        address _authCenter,
        address _fundsProvider,
        address _oneInchRouter,
        address _feeTo
    ) external {
        require(!flag, "BYDEFI: already initialized!");
        super.initialize();
        opManager = _opManager;
        accountManager = _accountManager;
        authCenter = _authCenter;
        fundsProvider = _fundsProvider;
        oneInchRouter = _oneInchRouter;
        feeTo = _feeTo;
        flag = true;
    }

    function doSwap(
        string memory _id,
        string memory _uniqueId,
        uint8 _assetFrom,
        uint8 _action,
        address _srcToken,
        address _dstToken,
        uint256 _srcAmount,
        uint256 _srcFeeAmount,
        bytes calldata _data
    ) external onlyAccess onlyRunning returns (uint256 returnAmount) {
        require(_assetFrom <= 1 && _action <= 1, "BYDEFI: assetFrom or action invalid!");
        require(_srcToken != Configure.ZERO_ADDRESS && _dstToken != Configure.ZERO_ADDRESS, "BYDEFI: invalid token input!");
        require(_srcAmount > 0, "BYDEFI: src amount should gt 0!");

        returnAmount = _swapInternal(_id, _uniqueId, _assetFrom, _action, _srcToken, _dstToken, _srcAmount, _srcFeeAmount, _data);
    }

    struct LocalVars {
        address from;
        address to;
        uint256 amt;
        uint256 value;
        uint256 initalBal;
        uint256 finalBal;
        bool success;
    }

    function _swapInternal(
        string memory _id,
        string memory _uniqueId,
        uint8 _assetFrom,
        uint8 _action,
        address _srcToken,
        address _dstToken,
        uint256 _srcAmount,
        uint256 _srcFeeAmount,
        bytes calldata _data
    ) internal returns (uint256 returnAmount) {
        LocalVars memory vars;
        (vars.from, vars.to) = makeData(_assetFrom, _action, _id, _srcToken, _dstToken);

        vars.amt = IAccount(vars.from).pull(_srcToken, _srcAmount, address(this));
        require(vars.amt == _srcAmount, "BYDEFI: invalid src amount input!");
        vars.initalBal = _getTokenBal(IERC20(_dstToken));

        if (Configure.ETH_ADDRESS == _srcToken) {
            vars.value = _srcAmount;
        } else {
            _srcToken.safeApprove(oneInchRouter, vars.amt);
        }

        (vars.success, ) = oneInchRouter.call{ value: vars.value }(_data);
        if (!vars.success) {
            revert("BYDEFI: 1Inch swap failed");
        }

        vars.finalBal = _getTokenBal(IERC20(_dstToken));

        unchecked {
            returnAmount = vars.finalBal - vars.initalBal;
        }

        // double check, in case dstToken mismatch calldata
        require(returnAmount > 0, "BYDEFI: swap error!");

        if (Configure.ETH_ADDRESS != _dstToken) {
            _dstToken.safeApprove(vars.to, returnAmount);
            IAccount(vars.to).push(_dstToken, returnAmount);
        } else {
            IAccount(vars.to).push{ value: returnAmount }(_dstToken, returnAmount);
        }

        if (_srcFeeAmount > 0 && feeTo != Configure.ZERO_ADDRESS) {
            IAccount(vars.from).pull(_srcToken, _srcFeeAmount, feeTo);
            emit Fee(_uniqueId, feeTo, _srcToken, _srcFeeAmount);
        }

        emit Swap(_id, _uniqueId, _assetFrom, _action, _srcToken, _dstToken, vars.from, vars.to, feeTo, vars.amt, _srcFeeAmount, returnAmount);
    }

    function directlyWithdraw(
        string memory _id,
        string memory _uniqueId,
        address _token,
        uint256 _amount,
        uint256 _feeAmount
    ) external onlyAccess onlyRunning returns (uint256 amt) {
        require(IFundsProvider(fundsProvider).isSupported(_token), "BYDEFI: directlyWithdraw unsupported token!");
        require(_amount > 0, "BYDEFI: withdraw amount should gt 0!");

        address account = _getAccountInternal(_id);
        require(account != Configure.ZERO_ADDRESS, "BYDEFI: invalid id");

        amt = IAccount(account).pull(_token, _amount, fundsProvider);

        if (_feeAmount > 0 && feeTo != Configure.ZERO_ADDRESS) {
            IAccount(account).pull(_token, _feeAmount, feeTo);
        }

        emit DirectlyWithdraw(_id, _uniqueId, _token, amt);
        emit Fee(_uniqueId, feeTo, _token, _feeAmount);
    }

    function swapWithdraw(
        string memory _id,
        string memory _uniqueId,
        address _srcToken,
        address _dstToken,
        uint256 _srcAmount,
        uint256 _srcFeeAmount,
        bytes calldata _data
    ) external onlyAccess onlyRunning returns (uint256 amt) {
        amt = _swapInternal(_id, _uniqueId, uint8(AssetFrom.ACCOUNT), uint8(Action.PRECROSS), _srcToken, _dstToken, _srcAmount, _srcFeeAmount, _data);

        emit SwapWithdraw(_id, _uniqueId, _srcToken, _dstToken, _srcAmount, amt);
        emit Fee(_uniqueId, feeTo, _srcToken, _srcFeeAmount);
    }

    function createAccount(string memory _id) external onlyAccess returns (address account) {
        account = IAccountManager(accountManager).createAccount(_id);

        emit CreateAccount(_id, account);
    }

    function getBalanceById(string memory _id, address[] memory _tokens) external view returns (uint256 balance, uint256[] memory amounts) {
        address account = _getAccountInternal(_id);
        require(account != Configure.ZERO_ADDRESS, "BYDEFI: invalid id");
        (balance, amounts) = IAccount(account).getBalance(_tokens);
    }

    function makeData(
        uint8 _assetFrom,
        uint8 _action,
        string memory _id,
        address _srcToken,
        address _dstToken
    ) internal returns (address from, address to) {
        address account = _getAccountInternal(_id);
        if (account == Configure.ZERO_ADDRESS) {
            account = IAccountManager(accountManager).createAccount(_id);
        }

        if (uint8(AssetFrom.FUNDSPROVIDER) == _assetFrom && uint8(Action.SWAP) == _action) {
            // by offchain account, usdt provided by funds provider, swap
            require(IFundsProvider(fundsProvider).isSupported(_srcToken), "BYDEFI: src token not supported by funds provider!");
            from = fundsProvider;
            to = account;
        } else if (uint8(AssetFrom.ACCOUNT) == _assetFrom && uint8(Action.SWAP) == _action) {
            // by onchain account, token provided by sub constract, swap
            from = account;
            to = account;
        } else if (uint8(AssetFrom.ACCOUNT) == _assetFrom && uint8(Action.PRECROSS) == _action) {
            // by onchain account, token provided by sub contract, cross chain
            require(IFundsProvider(fundsProvider).isSupported(_dstToken), "BYDEFI: dst token not supported by funds provider!");
            from = account;
            to = fundsProvider;
        } else {
            revert("BYDEFI: invalid asset from and action combination!");
        }
    }

    function updateOneInchRouter(address _router) external onlyOwner {
        address pre = oneInchRouter;
        oneInchRouter = _router;

        emit UpdateOneInchRouter(pre, oneInchRouter);
    }

    function setOpManager(address _opManager) external onlyOwner {
        address pre = opManager;
        opManager = _opManager;
        emit SetOpManager(pre, _opManager);
    }

    function setAccountManager(address _accManager) external onlyOwner {
        address pre = accountManager;
        accountManager = _accManager;
        emit SetAccountManager(pre, _accManager);
    }

    function setAuthCenter(address _authCenter) external onlyOwner {
        address pre = authCenter;
        authCenter = _authCenter;
        emit SetAuthCenter(pre, _authCenter);
    }

    function setFundsProvider(address _fundsProvider) external onlyOwner {
        address pre = fundsProvider;
        fundsProvider = _fundsProvider;
        emit SetFundsProvider(pre, _fundsProvider);
    }

    function setFeeTo(address _feeTo) external onlyOwner {
        address pre = feeTo;
        feeTo = _feeTo;
        emit SetFeeTo(pre, _feeTo);
    }

    function push(address _token, uint256 _amt) external payable override returns (uint256 amt) {
        _token;
        _amt;
        amt;
        revert();
    }

    function pull(
        address _token,
        uint256 _amt,
        address _to
    ) external override returns (uint256 amt) {
        amt = _pull(_token, _amt, _to);
    }

    function getAccount(string memory _id) external view returns (address account) {
        return _getAccountInternal(_id);
    }

    function _getAccountInternal(string memory _id) internal view returns (address account) {
        account = IAccountManager(accountManager).getAccount(_id);
    }

    function _getTokenBal(IERC20 token) internal view returns (uint256 _amt) {
        _amt = address(token) == Configure.ETH_ADDRESS ? address(this).balance : token.balanceOf(address(this));
    }

    function useless() public pure returns (uint256 a, string memory s) {
        a = 100;
        s = "hello world!";
    }
}

