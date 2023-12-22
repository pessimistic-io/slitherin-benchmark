// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./Ownable.sol";
import "./ECDSA.sol";
import "./IERC20.sol";
import "./IUniswapV2Router02.sol";

contract FaveBetIDO is Ownable {
    using ECDSA for bytes32;
    using Strings for uint256;

    address public swapRouterAddress;
    mapping(address => uint256) public userInvested;
    mapping(address => bool) public allowedInvestmentTokens;
    mapping(address => uint256) public investmentTokenDecimals;
    address public defaultInvestmentToken;
    uint256 public idoStartTime;
    uint256 public idoEndTime;
    uint256 public userInvestmentLimit;
    address[] public kycOperators;
    mapping(bytes32 => bool) public signatureUsed;
    bool public useSignatureVerification;

    event Invest(
       address indexed investor,
       uint256 indexed investedAmount,
       address indexed investmentToken,
       bytes32 signatureRandomBytes,
       bytes32 signaturesHash
    );

    constructor(
        address _swapRouterAddress,
        address[] memory _allowedinvestmentTokens,
        uint256[] memory _investmentTokenDecimals,
        uint256 _idoStartTime,
        uint256 _idoEndTime,
        uint256 _userInvestmentLimit,
        address[] memory _kycOperators
    ) Ownable() {
        swapRouterAddress = _swapRouterAddress;
        for (uint i = 0; i < _allowedinvestmentTokens.length; i++) {
            allowedInvestmentTokens[_allowedinvestmentTokens[i]] = true;
            investmentTokenDecimals[_allowedinvestmentTokens[i]] = _investmentTokenDecimals[i];
        }
        allowedInvestmentTokens[address(0)] = true;
        investmentTokenDecimals[address(0)] = 18;

        defaultInvestmentToken = _allowedinvestmentTokens[0];
        idoStartTime = _idoStartTime;
        idoEndTime = _idoEndTime;
        userInvestmentLimit = _userInvestmentLimit;
        for (uint i = 0; i < _kycOperators.length; i++)
            kycOperators.push(_kycOperators[i]);
    }

    function invest(
        address investmentToken,
        uint256 investmentAmount,
        uint256 signatureExpirationTime,
        bytes32 signatureRandomBytes,
        bytes[] memory signatures
    ) external payable {
        require(block.timestamp >= idoStartTime, "FaveBetIDO: Sale not started");
        require(block.timestamp < idoEndTime, "FaveBetIDO: Sale ended");
        require(allowedInvestmentTokens[investmentToken], "FaveBetIDO: Token not allowed"); 
        require(signatures.length == kycOperators.length, "FaveBetIDO: Invalid signature length");
        require(signatureExpirationTime >= block.timestamp, "FaveBetIDO: Signature expired");

        uint256 normalizedInvestmentAmount;
        if (investmentToken == address(0)) {
            require(msg.value == investmentAmount, "FaveBetIDO: msg.value is invalid");
            normalizedInvestmentAmount = _swapNativeToStable(investmentAmount);
        } else {
            require(IERC20(investmentToken).allowance(msg.sender, address(this)) >= investmentAmount, "FaveBetIDO: Insufficient ERC20 allowance"); 
            IERC20(investmentToken).transferFrom(msg.sender, address(this), investmentAmount);
            normalizedInvestmentAmount = investmentAmount;
        }
        normalizedInvestmentAmount = (normalizedInvestmentAmount * 1 ether) / (10 ** investmentTokenDecimals[investmentToken]);
        require(userInvested[msg.sender] + normalizedInvestmentAmount <= userInvestmentLimit, "FaveBetIDO: User max allocation reached");

        bytes32 signedMessage = createSignedMessage(abi.encodePacked(
            msg.sender,
            signatureRandomBytes,
            signatureExpirationTime
        ));
        bytes32 signaturesHash;
        for (uint i = 0; i < kycOperators.length; i++) {
            bytes32 signatureHash = keccak256(signatures[i]);
            if (useSignatureVerification) {
                address recoveredSigner = recoverSigner(signedMessage, signatures[i]);
                require(!signatureUsed[signatureHash], "FaveBetIDO: Signature has already been used"); 
                require(recoveredSigner == kycOperators[i], "FaveBetIDO: Invalid recovered signer");
            }
            signatureUsed[signatureHash] = true;
            signaturesHash = keccak256(abi.encodePacked(signaturesHash, signatureHash));
        }

        userInvested[msg.sender] += normalizedInvestmentAmount;
        emit Invest(
            msg.sender,
            investmentAmount,
            investmentToken,
            signatureRandomBytes,
            signaturesHash
        );
    }

    function withdrawNative(uint256 amount) external onlyOwner {
        payable(owner()).transfer(amount);
    }

    function withdrawERC20(address tokenAddress, uint256 amount) external onlyOwner {
        IERC20(tokenAddress).transfer(owner(), amount);
    }

    function setIdoStartTime(uint256 _idoStartTime) external onlyOwner {
        idoStartTime = _idoStartTime;
    }

    function setIdoEndTime(uint256 _idoEndTime) external onlyOwner {
        idoEndTime = _idoEndTime;
    }

    function setAllowedInvestmentToken(address tokenAddress, bool allowed) external onlyOwner {
        allowedInvestmentTokens[tokenAddress] = allowed;
    }

    function setInvestmentTokenDecimals(address tokenAddress, uint256 decimals) external onlyOwner {
        investmentTokenDecimals[tokenAddress] = decimals;
    }

    function setSwapRouterAddress(address _swapRouterAddress) external onlyOwner {
        swapRouterAddress = _swapRouterAddress;
    }

    function setDefaultInvestmentToken(address _defaultInvestmentToken) external onlyOwner {
        defaultInvestmentToken = _defaultInvestmentToken;
    }

    function setUserInvestmentLimit(uint256 _userInvestmentLimit) external onlyOwner {
        userInvestmentLimit = _userInvestmentLimit;
    }

    function setKycOperators(address[] memory _kycOperators) external onlyOwner {
        kycOperators = _kycOperators;
    }

    function setUseSignatureVerification(bool _useSignatureVerification) external onlyOwner {
        useSignatureVerification = _useSignatureVerification;
    }

    function _swapNativeToStable(uint256 swapAmount) internal returns (uint256) {
        if (swapAmount == 0) return 0;
        if (swapRouterAddress == address(0)) return 0;
        uint256 defaultTokenBalanceBefore = IERC20(defaultInvestmentToken).balanceOf(address(this));
        address[] memory swapPath = new address[](2);
        swapPath[0] = IUniswapV2Router02(swapRouterAddress).WETH();
        swapPath[1] = defaultInvestmentToken;
        IUniswapV2Router02(swapRouterAddress).swapExactETHForTokens{ value: swapAmount }(
            0,
            swapPath,
            address(this),
            block.timestamp
        );
        uint256 defaultTokenBalanceAfter = IERC20(defaultInvestmentToken).balanceOf(address(this));
        return defaultTokenBalanceAfter - defaultTokenBalanceBefore;
    }

    function createSignedMessage(bytes memory encodedData) internal pure returns (bytes32) {
        return keccak256(encodedData).toEthSignedMessageHash();
    }

    function splitSignature(bytes memory sig)
        internal
        pure
        returns (uint8 v, bytes32 r, bytes32 s) {
        require(sig.length == 65);

        assembly {
            // first 32 bytes, after the length prefix.
            r := mload(add(sig, 32))
            // second 32 bytes.
            s := mload(add(sig, 64))
            // final byte (first byte of the next 32 bytes).
            v := byte(0, mload(add(sig, 96)))
        }

        return (v, r, s);
    }

    function recoverSigner(bytes32 message, bytes memory sig)
        internal
        pure
        returns (address) {
        (uint8 v, bytes32 r, bytes32 s) = splitSignature(sig);
        return ecrecover(message, v, r, s);
    }

    receive() external payable {}   
}
