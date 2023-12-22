// SPDX-License-Identifier: MIT
pragma solidity ^0.8.1;
import "./IERC20.sol";
import "./ERC20.sol";
import "./draft-ERC20Permit.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";

interface IMessageTransmitter {
    function receiveMessage(bytes calldata message, bytes calldata attestation) external returns (bool success);
}

interface IRouter {
    function swapExactTokensForETH(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline) external returns (uint[] memory amounts);
    function getAmountsOut(uint amountIn, address[] memory path) external view returns (uint[] memory amounts);
}

contract Settler is ReentrancyGuard {
    address internal admin;
    using SafeERC20 for ERC20;
    mapping(address => uint) internal tokenBalance;
    mapping(address => uint) internal coinBalance;
    ERC20 public token;
    IMessageTransmitter messageTransmitter;
    IRouter router;
    address[] public path;

    error NotAdmin();
    error TransactionFailed();

    event Deposit(address indexed sender, uint256 amount, string detail);
    event Withdrawal(uint256 amount, string detail);
    event Transfer(address indexed recipient, uint256 amount, string detail);

    constructor(address _tokenAddress, address _messageTransmitterAddr, address _routerAddr, address _wrappedCoin) {
        token = ERC20(_tokenAddress);
        admin = msg.sender;
        messageTransmitter = IMessageTransmitter(_messageTransmitterAddr);
        router = IRouter(_routerAddr);
        path = [_tokenAddress, _wrappedCoin];
    }
    
    struct coinSettleWithFeeInput {
        address _to;
        uint256 _fee;
        uint256 _slippageInt;
        uint _slippageDecimal;
    }

    modifier OnlyAdmin {
        if(msg.sender != admin) revert NotAdmin();
        _;
    }

    // --------------------------------------- For Admin ---------------------------------------
    
    // Withdraw the fees(USDC) to cover the gas consumed on the target chain when the recipient's coin is insufficient to pay for gas.
    function withdrawToken(uint256 _amount) external OnlyAdmin {
        require(tokenBalance[admin] >= _amount, "Insufficient token balance");
        tokenBalance[admin] -= _amount;
        token.safeTransfer(admin, _amount);
        emit Withdrawal(_amount, "Token withdrawal");
    }

    // To avoid coin from being transferred to this contract address, here is a function that allows EOAs to get their coin back.
    function withdrawCoin(uint256 _amount) external nonReentrant {
        require(coinBalance[msg.sender] >= _amount, "Insufficient token balance");
        coinBalance[msg.sender] -= _amount;
        (bool success, ) = msg.sender.call{value: _amount}("");
        require(success, "Failed to withdraw coin");
        emit Withdrawal(_amount, "Coin withdrawal");
    }

    // --------------------------------------- Settle ---------------------------------------

    // tokenSettleWithFee() is called when the recipient of the swap(settled in token) has insufficient coin to pay for gas.
    // 1. Call messageTransmitter's receiveMessage to get the new-minted USDC. Get the balance change of address(this).
    // 2. Calculate the final transferred amount which equals _balanceChange minus _fee.(_fee is USDC which is equivalent to the total cost of gas)
    // 3. After calculation, transfer the final amount of token to the recipient addresss.
    function tokenSettleWithFee(bytes calldata _message, bytes calldata _attestation, address _to, uint256 _fee) public nonReentrant returns (bool) {
        uint _balanceChange = _withdrawFromMessageTransmitter(_message, _attestation, _to);
        require(_fee > 0 && _fee < _balanceChange, "Invalid fee");
        uint _amount = _balanceChange - _fee;
        tokenBalance[admin] += _fee;
        _transferToken(_to, _amount);
        return true;
    }

    // coinSettleWithFee() is called when the recipient of the swap(settled in coin) has insufficient coin to pay for gas.
    // 1. Call messageTransmitter's receiveMessage to get the new-minted USDC. Get the balance change of address(this).
    // 2. Calculate the final transferred amount which equals _tokenBalanceChange minus _fee.(_fee is USDC which is equivalent to the total cost of gas)
    // 3. Swap token for coin By using router contract. 
    // 4. Finally，get the amount of coin gained after the swap, and send the coin to recipient.
    // Notice: slippage is regarded as the combination of its integer part and its decimal.
    // _slippageInt is the integer part of slippage, and _slippageDecimal means the decimal length of slippage.
    // e.g. 0.05%: _slippageInt is 5. _slippageDecimal = 4.
    function coinSettleWithFee(bytes calldata _message, bytes calldata _attestation, coinSettleWithFeeInput memory info) public nonReentrant returns (bool) {
        uint _tokenBalanceChange = _withdrawFromMessageTransmitter(_message, _attestation, info._to);
        require(info._fee > 0 && info._fee < _tokenBalanceChange, "Invalid fee");
        uint _amount = _tokenBalanceChange - info._fee;
        tokenBalance[info._to] -= _tokenBalanceChange;
        tokenBalance[admin] += info._fee;
        uint[] memory amountsOutArray = router.getAmountsOut(1000000, path);    // calculate the exchange rate using 1000000 as the input to ensure the accuracy
        uint swapOutWithoutSlippage = _amount * amountsOutArray[1] / 1000000;
        require(info._slippageInt >= 0 && info._slippageInt < 100, "Invalid slippage");
        uint _amountOutMin = swapOutWithoutSlippage * ((10 ** info._slippageDecimal) - info._slippageInt) / (10 ** info._slippageDecimal);
        uint _deadline = block.timestamp + 600;
        uint[] memory swapOutResultArray = router.swapExactTokensForETH(_amount, _amountOutMin, path, info._to, _deadline);
        emit Transfer(info._to, swapOutResultArray[0], "Coin transferred");
        return true;
    }

    // --------------------------------------- Transfer ---------------------------------------
    
    function _transferToken(address _to, uint256 _amount) internal {
        require(tokenBalance[_to] >= _amount, "Insufficient token balance");
        tokenBalance[_to] -= _amount;
        token.safeTransfer(_to, _amount);
        emit Transfer(_to, _amount, "Token transferred");
    }

    // --------------------------------------- Withdraw From MessageTransmitter ---------------------------------------

    function _withdrawFromMessageTransmitter(bytes calldata _message, bytes calldata _attestation, address _to) internal returns (uint) {
        uint poolBalanceBefore = token.balanceOf(address(this));
        bool success = messageTransmitter.receiveMessage(_message, _attestation);
        require(success, "withdraw from messageTransmitter failed");
        uint balanceChange = token.balanceOf(address(this)) - poolBalanceBefore;
        require(balanceChange > 0, "No token received");
        tokenBalance[_to] += balanceChange;
        return balanceChange;
    }

    // --------------------------------------- Get Value ---------------------------------------

    function getTokenSymbol() public view returns (string memory) {
        return token.symbol();
    }

    function getTokenBalance(address _user) public view returns (uint) {
        return tokenBalance[_user];
    }

    function getPoolTokenBalance() external view OnlyAdmin() returns (uint) {
        return token.balanceOf(address(this));
    }

    function getMyCoinBalance() external view returns (uint) {
        return coinBalance[msg.sender];
    }

    fallback() external payable {
        coinBalance[msg.sender] += msg.value;
        emit Deposit(msg.sender, msg.value, "coin deposited by fallback");
    }
}
