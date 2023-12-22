// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.4;

import "./console.sol";
import "./Strings.sol";
import "./Ownable.sol";
import "./SafeMath.sol";
import "./IERC20.sol";
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

contract Sedn is ERC2771Context, Ownable, IUserRequest {
    IERC20 public usdcToken;
    IRegistry public registry;
    uint256 public paymentCounter;
    address public addressDelegate;
    address public trustedVerifyAddress;
    uint256 public nonce = 0;

    event PreferredAddressSet(string phone, address to);

    struct Payment {
        address from;
        uint256 amount;
        bool completed;
        bytes32 secret;
    }

    mapping(bytes32 => Payment) private payments;

    constructor(
        address _usdcTokenAddressForChain,
        address _registryDeploymentAddressForChain,
        address _trustedVerifyAddress,
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
    }

    function _msgSender() internal view override(Context, ERC2771Context)
        returns (address sender) {
        sender = ERC2771Context._msgSender();
    }

    function _msgData() internal view override(Context, ERC2771Context)
        returns (bytes calldata) {
        return ERC2771Context._msgData();
    }

    function sedn(uint256 _amount, bytes32 secret) external {
        require(_amount > 0, "Amount must be greater than 0");
        require(usdcToken.transferFrom(_msgSender(), address(this), _amount), "Transfer failed");
        require(payments[secret].secret != secret, "Can not double set secret");
        payments[secret] = Payment(_msgSender(), _amount, false, secret);
    }

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
        require(keccak256(abi.encodePacked(solution)) == payments[secret].secret, "Incorrect answer");
        require(payments[secret].secret == secret, "Secret not found");
        require(payments[secret].from != address(0), "payment not found");
        require(payments[secret].completed == false, "Payment already completed");
        require(payments[secret].amount == amount, "Amount does not match");
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
        _checkClaim(solution, secret, _msgSender(), payments[secret].amount, _till, _v, _r, _s);
        usdcToken.approve(address(this), payments[secret].amount);
        require(usdcToken.transferFrom(address(this), _msgSender(), payments[secret].amount), "transferFrom failed");
        payments[secret].completed = true;
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
        _checkClaim(solution, secret, _msgSender(), payments[secret].amount, _till, _v, _r, _s);
        console.log("Bridge and claiming funds", payments[secret].amount, _msgSender());
        usdcToken.approve(address(registry), payments[secret].amount);
        usdcToken.approve(bridgeImpl, payments[secret].amount);
        registry.outboundTransferTo(_userRequest);
        payments[secret].completed = true;
    }

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

