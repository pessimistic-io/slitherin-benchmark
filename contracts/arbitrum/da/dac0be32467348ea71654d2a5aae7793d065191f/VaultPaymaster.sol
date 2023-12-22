// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

/* solhint-disable reason-string */

import {IDelegatedManagerFactory} from "./IDelegatedManagerFactory.sol";
import {ISignalSuscriptionExtension} from "./ISignalSuscriptionExtension.sol";
import {IOwnable} from "./IOwnable.sol";
import {IUniswapV2Router} from "./IUniswapV2Router.sol";
import {IERC20} from "./IERC20.sol";
import "./OwnableUpgradeable.sol";
import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./IPaymaster.sol";
import "./IEntryPoint.sol";

/**
 * A sample paymaster that defines itself as a token _to pay for gas.
 * The paymaster IS the token _to use, since a paymaster cannot use an external contract.
 * Also, the exchange rate has _to be fixed, since it can't reference an external Uniswap or other exchange contract.
 * subclass should override "getTokenValueOfEth" _to provide actual token exchange rate, settable by the owner.
 * Known Limitation: this paymaster is exploitable when put into a batch with multiple ops (of different accounts):
 * - while a single op can't exploit the paymaster (if postOp fails _to withdraw the tokens, the user's op is reverted,
 *   and then we know we can withdraw the tokens), multiple ops with different senders (all using this paymaster)
 *   in a batch can withdraw funds from 2nd and further ops, forcing the paymaster itself _to pay (from its deposit)
 * - Possible workarounds are either use a more complex paymaster scheme (e.g. the DepositPaymaster) or
 *   _to whitelist the account and the called method ids.
 */
contract VaultPaymaster is
    Initializable,
    OwnableUpgradeable,
    UUPSUpgradeable,
    IPaymaster
{
    //calculated cost of the postOp
    uint256 public constant COST_OF_POST = 15000;

    //account token account
    mapping(address => uint256) public user2balance;

    IUniswapV2Router public router;

    uint256 internal DIVISOR;

    address public weth;

    ISignalSuscriptionExtension internal signalSuscriptionExtension;

    IDelegatedManagerFactory internal delegatedManagerFactory;

    uint256 internal fee;

    event Deposit(address user, address to, address token, uint256 amount);

    event Withdraw(address user, address to, address token, uint256 amount);

    event WarnLine(address jasperVault, uint256 balance);

    event Unsubscribe(address target, address jasperVault, uint256 balance);

    event  SetSetting(IEntryPoint _entryPoint,IUniswapV2Router _router,uint256 _fee,address _weth,address _eth,ISignalSuscriptionExtension _signalSuscriptionExtension,IDelegatedManagerFactory _delegatedManagerFactory);


    address public ETH_TOKEN_ADDRESS;

    IEntryPoint public entryPoint;

    mapping(address => address[]) internal token2path;
    event SetTokenPath(address token, address[] path);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        IEntryPoint _entryPoint,
        IUniswapV2Router _router,
        address _weth,
        uint256 _fee,
        ISignalSuscriptionExtension _signalSuscriptionExtension,
        IDelegatedManagerFactory _delegatedManagerFactory
    ) public initializer {
        entryPoint = _entryPoint;
        router = _router;
        weth = _weth;
        fee = _fee;
        signalSuscriptionExtension = _signalSuscriptionExtension;
        delegatedManagerFactory = _delegatedManagerFactory;
        __Ownable_init();
        __UUPSUpgradeable_init();
        DIVISOR = 10 ** 18;
        ETH_TOKEN_ADDRESS = 0x0000000000000000000000000000000000000000;
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    function setSetting(
        IEntryPoint _entryPoint,
        IUniswapV2Router _router,
        uint256 _fee,
        address _weth,
        address _eth,
        ISignalSuscriptionExtension _signalSuscriptionExtension,
        IDelegatedManagerFactory _delegatedManagerFactory
    ) external onlyOwner {
        entryPoint = _entryPoint;
        router = _router;
        fee = _fee;
        signalSuscriptionExtension = _signalSuscriptionExtension;
        delegatedManagerFactory = _delegatedManagerFactory;
        weth = _weth;
        ETH_TOKEN_ADDRESS = _eth;
        emit SetSetting(_entryPoint,_router,_fee,_weth,_eth,_signalSuscriptionExtension,_delegatedManagerFactory);
       
    }

    function setTokenToPath(
        address _token,
        address[] calldata _path
    ) external onlyOwner {
        require(_path.length > 0, "path length greater than zero");
        require(_token==_path[0],"token not equal to path[0]");
        token2path[_token] = _path;
        emit SetTokenPath(_token, _path);
    }

    function deposit(uint256 _value) internal {
        entryPoint.depositTo{value: _value}(address(this));
    }

    function depositBalance(
        address _to,
        address _token,
        uint256 _amount,
        uint256 _minAmount
    ) external payable {
        if (address(_token) == ETH_TOKEN_ADDRESS) {
            depositEth(_to);
        } else {
            address[] memory _path = token2path[_token];
            require(_path.length > 0, "path is not exist");
            depositToken(_to, IERC20(_token), _path, _amount,_minAmount);
        }
    }

    /**
     * withdraw value from the deposit
     * @param withdrawAddress target to send to
     * @param amount to withdraw
     */
    function withdrawTo(
        address payable withdrawAddress,
        uint256 amount
    ) internal {
        entryPoint.withdrawTo(withdrawAddress, amount);
    }

    //deposit   Eth
    function depositEth(address _to) internal {
        require(msg.value > 0, "deposit balance less than zero");
        deposit(msg.value);
        user2balance[_to] += msg.value;
        emit Deposit(msg.sender, _to, weth, msg.value);
    }

    //deposit  Token
    function depositToken(
        address _to,
        IERC20 _token,
        address[] memory _path,
        uint256 _amount,
        uint256 _minAmount
    ) internal {
        require(_amount > 0, "amount less than zero");
        bool success=_token.transferFrom(msg.sender, address(this), _amount);
        require(success,"transferFrom fail");
        _token.approve(address(router), _amount);
        uint256 swapNum = _swapExactTokensForETH(_path, _amount);
        require(swapNum>=_minAmount,"swap balance less than minAmount");
        deposit(swapNum);
        user2balance[_to] += swapNum;
        emit Deposit(msg.sender, _to, address(_token), _amount);
    }

    function withdrawEth(address _to, uint256 _amount) external {
        uint256 preBalance = user2balance[msg.sender];
        require(preBalance >= _amount, "withdraw weth greater than balance");
        user2balance[msg.sender] = preBalance - _amount;
        withdrawTo(payable(_to), _amount);
        emit Withdraw(msg.sender, _to, weth, _amount);
    }

    function withdrawToken(
        address _to,
        IERC20 _receiveToken,
        uint256 _balance,
        uint256 _minReceiveToken
    ) external {
        uint256 preBalance = user2balance[msg.sender];
        require(preBalance >= _balance, "amount greater than balance ");
        address[] memory _path = token2path[address(_receiveToken)];
        require(_path.length > 0, "path is not exist");
        user2balance[msg.sender] = preBalance - _balance;
        withdrawTo(payable(this), _balance);
        address[] memory newPath=reversalArray(_path);
        uint256 swapNum=_swapExactETHForTokens(_to, newPath, _balance);
        require(swapNum>=_minReceiveToken,"swap balance less than minReceiveToken");
        emit Withdraw(msg.sender, _to, weth, _balance);
    }

    function getPath(address _token) external view returns (address[] memory) {
        address[] memory path=token2path[_token];
        return path;
    }

    function reversalArray(address[] memory list) internal pure returns(address[] memory){
         uint256 len=list.length;
         address[] memory newList=new address[](len);
         uint256 index=0;
         for(uint256 i=len;i>0;i--){
             newList[index]=list[i-1];
             index++;
         }
         return newList;
    }

    //swap
    function _swapExactTokensForETH(
        address[] memory _path,
        uint256 _amountIn
    ) internal returns (uint256) {
        uint deadline = block.timestamp + 300;
        address _weth=_path[_path.length-1];
        require(_weth==weth,"swap path incorrectness");
        uint[] memory amounts = router.swapExactTokensForETH(
            _amountIn,
            0,
            _path,
            address(this),
            deadline
        );
        return amounts[amounts.length-1];
    }

    function _swapExactETHForTokens(
        address _to,
        address[] memory _path,
        uint256 _amountIn
    ) internal returns (uint256) {
        uint deadline = block.timestamp + 300;
        address _weth=_path[0];
        require(_weth==weth,"swap path incorrectness");
        uint[] memory amounts = router.swapExactETHForTokens{value: _amountIn}(
            0,
            _path,
            _to,
            deadline
        );
        return amounts[amounts.length-1];
    }

    function unlockStake() external onlyOwner {
        entryPoint.unlockStake();
    }

    function getDeposit() public view returns (uint256) {
        return entryPoint.balanceOf(address(this));
    }

    function withdrawStake(address payable withdrawAddress) external onlyOwner {
        entryPoint.withdrawStake(withdrawAddress);
    }

    function addStake(uint32 unstakeDelaySec) external payable onlyOwner {
        entryPoint.addStake{value: msg.value}(unstakeDelaySec);
    }

    function validatePaymasterUserOp(
        UserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 maxCost
    ) external override returns (bytes memory context, uint256 validationData) {
        _requireFromEntryPoint();
        return _validatePaymasterUserOp(userOp, userOpHash, maxCost);
    }

    function _requireFromEntryPoint() internal virtual {
        require(msg.sender == address(entryPoint), "Sender not EntryPoint");
    }

    /**
     * validate the request:
     * if this is a constructor call, make sure it is a known account.
     * verify the sender has enough tokens.
     * (since the paymaster is also the token, there is no notion of "approval")
     */
    //payMaster->
    function _validatePaymasterUserOp(
        UserOperation calldata userOp,
        bytes32 /*userOpHash*/,
        uint256 requiredPreFund
    ) internal view returns (bytes memory context, uint256 validationData) {
        // verificationGasLimit is dual-purposed, as gas limit for postOp. make sure it is high enough
        // make sure that verificationGasLimit is high enough to handle postOp
        uint256 opFee = (requiredPreFund * fee) / DIVISOR;
        require(
            userOp.verificationGasLimit > COST_OF_POST,
            "Paymaster: gas too low for postOp"
        );
        address owner = IOwnable(userOp.sender).owner();
        require(
            user2balance[owner] >= (requiredPreFund + opFee),
            "Paymaster Validate: not sufficient funds"
        );
        return (abi.encode(userOp.sender), 0);
    }

    /// @inheritdoc IPaymaster
    function postOp(
        PostOpMode mode,
        bytes calldata context,
        uint256 actualGasCost
    ) external override {
        _requireFromEntryPoint();
        _postOp(mode, context, actualGasCost);
    }

    /**
     * actual charge of user.
     * this method will be called just after the user's TX with mode==OpSucceeded|OpReverted (account pays in both cases)
     * BUT: if the user changed its balance in a way that will cause  postOp to revert, then it gets called again, after reverting
     * the user's TX , back to the state it was before the transaction started (before the validatePaymasterUserOp),
     * and the transaction should succeed there.    _validatePaymasterUserOp->    call ->_postOp   userOp[]
     */

    function _postOp(
        PostOpMode mode,
        bytes calldata context,
        uint256 actualGasCost
    ) internal {
        //we don't really care about the mode, we just pay the gas with the user's tokens.
        (mode);
        address sender = abi.decode(context, (address));
        address owner = IOwnable(sender).owner();
        uint256 charge = actualGasCost + COST_OF_POST;
        uint256 balance = user2balance[owner];
        uint256 opFee = (charge * fee) / DIVISOR;
        require(balance >= (charge+opFee), "Paymaster Post:not sufficient funds");
        address manager = IOwnable(address(this)).owner();
        user2balance[manager] += opFee;
        user2balance[owner] = balance - charge - opFee;   
        //compensate caller
        settleFollowers(sender, charge + opFee);
    }

    function settleFollowers(address sender, uint256 totalGasCost) internal {
        address jasperVault = delegatedManagerFactory.account2setToken(sender);

        bool isExectueFollow = signalSuscriptionExtension.getExectueFollow(
            jasperVault
        );

        if (isExectueFollow) {
            address[] memory folllowers = signalSuscriptionExtension.getFollowers(jasperVault);          
            uint256 len = folllowers.length;
            if (len > 0) {
                uint256 averageGas = totalGasCost / (len + 1);
                uint256 totalAddGas;
                for (uint256 i = 0; i < len; i++) {
                    address setTokenSender = delegatedManagerFactory
                        .setToken2account(folllowers[i]);
                    address setTokenOwner = IOwnable(setTokenSender).owner();
                    uint256 setTokenOwnerBalance = user2balance[setTokenOwner];
                    if (setTokenOwnerBalance >= averageGas) {
                        user2balance[setTokenOwner] -= averageGas;
                        totalAddGas += averageGas;
                    } else {
                        user2balance[setTokenOwner] -= setTokenOwnerBalance;
                        totalAddGas += setTokenOwnerBalance;
                    }

                    if ( signalSuscriptionExtension.unsubscribeLine() >= user2balance[setTokenOwner]   ) {            
                        //unsubscribe
                        signalSuscriptionExtension.unsubscribeByExtension(folllowers[i], jasperVault);                   
                        emit Unsubscribe(folllowers[i], jasperVault, user2balance[setTokenOwner] );                    
                    } else if (signalSuscriptionExtension.warningLine() >=  user2balance[setTokenOwner]  ) {            
                        //warnLine
                        emit WarnLine(folllowers[i], user2balance[setTokenOwner] );                 
                    }

                }
                address owner = IOwnable(sender).owner();
                user2balance[owner] += totalAddGas;       
            }
            signalSuscriptionExtension.exectueFollowEnd(jasperVault);
        }
    }

    fallback() external payable {
        // custom function code
    }

    receive() external payable {
        // custom function code
    }
}

