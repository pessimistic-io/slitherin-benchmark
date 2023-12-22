// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.4;

import "./console.sol";
import "./Strings.sol";
import "./Ownable.sol";
import "./SafeMath.sol";
import "./IERC20.sol";
import "./ERC20.sol";
import "./ECDSA.sol";
import "./ERC2771Context.sol";
import "./MinimalForwarder.sol";

error SednError();

interface IUserRequest {
    /**
    // @param id route id of middleware to be used
    // @param optionalNativeAmount is the amount of native asset that the route requires 
    // @param inputToken token address which will be swapped to
    // BridgeRequest inputToken 
    // @param data to be used by middleware
    */
    struct MiddlewareRequest {
        uint256 id;
        uint256 optionalNativeAmount;
        address inputToken;
        bytes data;
    }

    /**
    // @param id route id of bridge to be used
    // @param optionalNativeAmount optinal native amount, to be used
    // when bridge needs native token along with ERC20    
    // @param inputToken token addresss which will be bridged 
    // @param data bridgeData to be used by bridge
    */
    struct BridgeRequest {
        uint256 id;
        uint256 optionalNativeAmount;
        address inputToken;
        bytes data;
    }

    /**
    // @param receiverAddress Recipient address to recieve funds on destination chain
    // @param toChainId Destination ChainId
    // @param amount amount to be swapped if middlewareId is 0  it will be
    // the amount to be bridged
    // @param middlewareRequest middleware Requestdata
    // @param bridgeRequest bridge request data
    */
    struct UserRequest {
        address receiverAddress;
        uint256 toChainId;
        uint256 amount;
        MiddlewareRequest middlewareRequest;
        BridgeRequest bridgeRequest;
    }
}

interface IRegistry is IUserRequest {
    function outboundTransferTo(UserRequest calldata _userRequest) external payable;
}

contract Sedn is ERC2771Context, Ownable, IUserRequest{
    IERC20 public usdcToken;
    IRegistry public registry;
    uint256 public paymentCounter;
    address public addressDelegate;
    address public trustedVerifyAddress;
    uint256 public nonce = 0;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    struct Payment {
        address from;
        uint256 amount;
        bool completed;
        bytes32 secret;
    }

    mapping(bytes32 => Payment) private _payments;
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    string private _name;
    string private _symbol;

    constructor(
        address _usdcTokenAddressForChain,
        address _registryDeploymentAddressForChain,
        address _trustedVerifyAddress,
        string memory name_,
        string memory symbol_,
        MinimalForwarder _trustedForwarder
    ) ERC2771Context(address(_trustedForwarder)) {
        console.log(
            "Deploying the Sedn Contract; USDC Token Address: %s; Socket Registry: %s",
            _usdcTokenAddressForChain,
            _registryDeploymentAddressForChain
        );
        usdcToken = IERC20(_usdcTokenAddressForChain);
        registry = IRegistry(_registryDeploymentAddressForChain);
        trustedVerifyAddress = _trustedVerifyAddress;
        _name = name_;
        _symbol = symbol_;
    }

    /**
     * ERC2771 Context
     */
    function _msgSender() internal view override(Context, ERC2771Context)
        returns (address sender) {
        sender = ERC2771Context._msgSender();
    }

    function _msgData() internal view override(Context, ERC2771Context)
        returns (bytes calldata) {
        return ERC2771Context._msgData();
    }

    /**
     * ERC20
     */
    function name() public view virtual returns (string memory) {
        return _name;
    }

    function symbol() public view virtual returns (string memory) {
        return _symbol;
    }

    function balanceOf(address account) public view virtual returns (uint256) {
        return _balances[account];
    }

    /**
     * SEDN
     */
    function sednUnknown(uint256 _amount, bytes32 secret) external {
        require(_amount > 0, "Amount must be greater than 0");
        require(usdcToken.transferFrom(_msgSender(), address(this), _amount), "Transfer failed");
        require(_payments[secret].secret != secret, "Can not double set secret");
        _payments[secret] = Payment(_msgSender(), _amount, false, secret);
    }

    function sednKnown(uint256 _amount, address to) external {
        require(_amount > 0, "Amount must be greater than 0");
        require(usdcToken.transferFrom(_msgSender(), address(this), _amount), "Transfer failed"); 
        // send money to contract
        // allocate balance to receiver
        _balances[to] += _amount;
    }

    function transferUnknown(uint256 balanceAmount, bytes32 secret) external {
        require(balanceAmount > 0, "Amount must be greater than 0");
        require(_payments[secret].secret != secret, "Can not double set secret");
        require(_msgSender() != address(0), "Transfer from the zero address");

        uint256 fromBalance = _balances[_msgSender()];
        require(fromBalance >= balanceAmount, "Transfer amount exceeds balance");
        _balances[_msgSender()] = fromBalance - balanceAmount; // may want to consider unchecked to save gas
        _payments[secret] = Payment(_msgSender(), balanceAmount, false, secret); // payment is completed
    }

    function transferKnown(uint256 amount, address to) public virtual returns (bool) {
        address from = _msgSender();
        require(from != address(0), "Transfer from the zero address");
        require(to != address(0), "Transfer to the zero address");
        uint256 fromBalance = _balances[from];
        require(fromBalance >= amount, "ERC20: transfer amount exceeds balance");
        unchecked {
            _balances[from] = fromBalance - amount;
            // Overflow not possible: the sum of all balances is capped by totalSupply, and the sum is preserved by
            // decrementing then incrementing.
            _balances[to] += amount;
        }

        emit Transfer(from, to, amount);
        return true;
    }

    function hybridUnknown(uint256 _amount, uint256 balanceAmount, bytes32 secret) external {
        // checks
        require(_amount > 0, "Amount must be greater than 0");
        require(balanceAmount > 0, "Amount must be greater than 0");
        uint256 fromBalance = _balances[_msgSender()];
        require(fromBalance >= balanceAmount, "Transfer amount exceeds balance");
        // create total amount
        uint256 totalAmount = _amount + balanceAmount;

        // transfer shit
        require(usdcToken.transferFrom(_msgSender(), address(this), _amount), "Transfer failed");
        _balances[_msgSender()] = fromBalance - balanceAmount; // may want to consider unchecked to save gas
        _payments[secret] = Payment(_msgSender(), totalAmount, false, secret); // payment is completed
    }

    function hybridKnown(uint256 _amount, uint256 balanceAmount, address to) external {
        // checks
        require(_amount > 0, "Amount must be greater than 0");
        require(balanceAmount > 0, "Amount must be greater than 0");
        uint256 fromBalance = _balances[_msgSender()];
        require(fromBalance >= balanceAmount, "Transfer amount exceeds balance");
        // create total amount
        uint256 totalAmount = _amount + balanceAmount;

        // transfer shit
        require(usdcToken.transferFrom(_msgSender(), address(this), _amount), "Transfer failed");
        _balances[_msgSender()] = fromBalance - balanceAmount; // may want to consider unchecked to save gas
        _balances[to] += totalAmount; // credit receiver
    } 

    /**
     * CLAIM
     */
    function _checkClaim(
        string memory solution,
        bytes32 secret,
        address receiver,
        uint256 amount,
        uint256 till,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) internal view {
        require(keccak256(abi.encodePacked(solution)) == _payments[secret].secret, "Incorrect answer");
        require(_payments[secret].secret == secret, "Secret not found");
        require(_payments[secret].from != address(0), "Payment not found");
        require(_payments[secret].completed == false, "Payment already completed");
        require(_payments[secret].amount == amount, "Amount does not match");
        require(block.timestamp < till, "Time expired");
        require(verify(amount, receiver, till, secret, nonce, _v, _r, _s), "Verification failed");
    }

    function claim(
        string memory solution,
        bytes32 secret,
        uint256 _till,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) public {
        _checkClaim(solution, secret, _msgSender(), _payments[secret].amount, _till, _v, _r, _s);
        require(_msgSender() != address(0), "Transfer to the zero address not possible");
        uint256 amount = _payments[secret].amount;
        _balances[_msgSender()] += amount; // Add amount to receiver
        _payments[secret].completed = true; // Mark payment as completed
    }

    /**
     * WITHDRAW
     */
    function withdraw(uint256 amount, address to) external {
        require(_msgSender() != address(0), "Transfer from the zero address");
        uint256 fromBalance = _balances[_msgSender()];
        require(fromBalance >= amount, "Transfer amount exceeds balance");
        usdcToken.approve(address(this), amount); // do we need this approve?
        require(usdcToken.transferFrom(address(this), to, amount), "transferFrom failed");
        _balances[_msgSender()] = fromBalance - amount;
    }

    function bridgeWithdraw(
        uint256 amount,
        UserRequest calldata _userRequest,
        address bridgeImpl
    ) external payable {
        address owner = _msgSender();
        address to = _userRequest.receiverAddress;
        require(owner != address(0), "bridgeWithdrawal from the zero address");
        require(to != address(0), "bridgeWithdrawal to the zero address");

        uint256 fromBalance = _balances[owner];
        require(fromBalance >= amount, "Withdrawal amount exceeds balance");
        _balances[owner] = fromBalance - amount;
        console.log("Bridge and claiming funds", amount, _msgSender());
        usdcToken.approve(address(registry), amount);
        usdcToken.approve(bridgeImpl, amount);
        registry.outboundTransferTo{value: msg.value}(_userRequest);
        emit Transfer(owner, bridgeImpl, amount);
    }

    function bridgeClaim(
        string memory solution,
        bytes32 secret,
        uint256 _till,
        uint8 _v,
        bytes32 _r,
        bytes32 _s,
        UserRequest calldata _userRequest,
        address bridgeImpl
    ) external payable {
        _checkClaim(solution, secret, _msgSender(), _payments[secret].amount, _till, _v, _r, _s);
        console.log("Bridge and claiming funds", _payments[secret].amount, _msgSender());
        usdcToken.approve(address(registry), _payments[secret].amount);
        usdcToken.approve(bridgeImpl, _payments[secret].amount);
        registry.outboundTransferTo{value: msg.value}(_userRequest);
        _payments[secret].completed = true;
    }

    /**
     * HELPERS
     */
    function setVerifier(address _trustedVerifyAddress) public onlyOwner {
        trustedVerifyAddress = _trustedVerifyAddress;
    }

    function increaseNonce() public onlyOwner {
        nonce++;
    }

    function getMessageHash(
        uint256 _amount,
        address _receiver,
        uint256 _till,
        bytes32 _secret,
        uint256 _nonce
    ) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(_amount, _receiver, _till, _secret, _nonce));
    }

    function getEthSignedMessageHash(bytes32 _messageHash) public pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", _messageHash));
    }

    function verify(
        uint256 _amount,
        address _receiver,
        uint256 _till,
        bytes32 _secret,
        uint256 _nonce,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) public view returns (bool) {
        bytes32 messageHash = getMessageHash(_amount, _receiver, _till, _secret, _nonce);
        bytes32 ethSignedMessageHash = getEthSignedMessageHash(messageHash);
        address recoveredAddress = ecrecover(ethSignedMessageHash, _v, _r, _s);
        return recoveredAddress == trustedVerifyAddress;
    }
}

