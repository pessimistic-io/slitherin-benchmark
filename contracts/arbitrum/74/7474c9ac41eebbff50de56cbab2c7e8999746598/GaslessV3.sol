pragma solidity >=0.8.0 <0.9.0;
//SPDX-License-Identifier: MIT

import "./Ownable.sol";
import "./ERC20.sol";
import "./draft-ERC20Permit.sol";
import "./ISwapRouter.sol";
import "./IQuoter.sol";
import "./TransferHelper.sol";
import "./console.sol";
import "./WrappedToken.sol";

contract GaslessV3 is Ownable {
    ISwapRouter public immutable swapRouter;
    IQuoter public immutable quoter;
    address public WrappedNative;
    address public constant SWAP_ROUTER_ADDRESS =
        0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address public constant QUOTER_ADDRESS =
        0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6;
    uint24 public constant feeTier = 3000;
    uint public balance = 0;
    uint public gasForSwap;
    uint public gasForApproval;
    bytes32 public DOMAIN_SEPARATOR;
    string public constant name = 'Flint Gasless';
    string public EIP712_VERSION = '1';
    mapping(address => uint) public nonces;
    mapping(address => uint) public approvalNonces;
    bytes32 public constant GASLESS_SWAP_TYPEHASH =
        keccak256(
            bytes(
                'SwapWithoutFees(uint amountIn,address tokenIn,address tokenOut,address userAddress,address[] path,uint24[] fees,uint nonce,bool isTokenOutNative)'
            )
        );
    bytes32 public constant GASLESS_APPROVAL_TYPEHASH =
        keccak256(
            bytes(
                'ApproveWithoutFees(address userAddress,address tokenAddress,uint approvalValue,uint approvalDeadline,address[] toNativePath,uint24[] toNativeFees,uint gasForApproval,uint nonce)'
            )
        );
    uint defaultGasPrice;

    struct SwapWithoutFeesParams {
        uint amountIn;
        address tokenIn;
        address tokenOut;
        address userAddress;
        address[] path;
        uint24[] fees;
        uint nonce;
        bool isTokenOutNative;
        address[] toNativePath;
        uint24[] toNativeFees;
        bytes32 sigR;
        bytes32 sigS;
        uint8 sigV;
    }

    struct ApproveWithoutFeesParams {
        address userAddress;
        bytes32 approvalSigR;
        bytes32 approvalSigS;
        uint8 approvalSigV;
        address tokenAddress;
        uint approvalValue;
        uint approvalDeadline;
        address[] toNativePath;
        uint24[] toNativeFees;
        uint gasForApproval;
        uint nonce;
        bytes32 sigR;
        bytes32 sigS;
        uint8 sigV;
    }

    constructor(
        address _wrappedNativeTokenAddress,
        uint _gasForSwap,
        uint _gasForApproval,
        uint _defaultGasPrice
    ) {
        swapRouter = ISwapRouter(SWAP_ROUTER_ADDRESS);
        quoter = IQuoter(QUOTER_ADDRESS);
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256(
                    'EIP712Domain(string name,string version,address verifyingContract,bytes32 salt)'
                ),
                keccak256(bytes(name)),
                keccak256(bytes(EIP712_VERSION)),
                address(this),
                bytes32(getChainId())
            )
        );
        WrappedNative = _wrappedNativeTokenAddress;
        gasForSwap = _gasForSwap;
        gasForApproval = _gasForApproval;
        defaultGasPrice = _defaultGasPrice;
    }

    function getBalance() public view returns (uint256) {
        return address(this).balance;
    }

    function transfer(address payable to, uint256 amount) public onlyOwner {
        (bool success, ) = to.call{value: amount}('');
        require(success);
    }

    function transferERC20(
        address payable to,
        uint256 amount,
        address tokenAddress
    ) public onlyOwner {
        ERC20 token = ERC20(tokenAddress);
        require(token.transfer(to, amount), 'Failed to transfer ERC20 token');
    }

    function setGasForSwap(uint newGasForSwap) external onlyOwner {
        gasForSwap = newGasForSwap;
    }

    function setGasForApproval(uint newGasForApproval) external onlyOwner {
        gasForApproval = newGasForApproval;
    }

    function setDefaultGasPrice(uint newDefaultGasPrice) external onlyOwner {
        defaultGasPrice = newDefaultGasPrice;
    }

    function swapWithoutFees(
        SwapWithoutFeesParams memory params
    ) external returns (uint256) {
        console.log('getting digest');
        bytes32 digest = _getDigest(
            params.amountIn,
            params.tokenIn,
            params.tokenOut,
            params.userAddress,
            params.path,
            params.fees,
            params.nonce,
            params.isTokenOutNative
        );
        console.log('verifying digest');
        _verifyDigest(
            digest,
            params.userAddress,
            params.sigR,
            params.sigS,
            params.sigV,
            params.nonce
        );

        if (params.tokenOut != WrappedNative) {
            params.isTokenOutNative = false;
        }

        console.log('internal swap');
        return _swapWithoutFees(params);
    }

    function _swapWithoutFees(
        SwapWithoutFeesParams memory params
    ) internal returns (uint256 amountOut) {
        ERC20 tokenContract = ERC20(params.tokenIn);

        require(
            tokenContract.transferFrom(
                params.userAddress,
                address(this),
                params.amountIn
            ),
            '[SWAP WITHOUT FEES] Failed to transfer from'
        );
        //check if we already have the allowance for fromTokenContract
        if (
            tokenContract.allowance(address(this), address(swapRouter)) <
            params.amountIn
        ) {
            console.log('approval');
            TransferHelper.safeApprove(
                params.tokenIn,
                address(swapRouter),
                0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
            );
        }

        //convert input token into Native to collect the fees
        uint swappedIn = 0;
        uint uniswapFees = tx.gasprice > 0
            ? gasForSwap * tx.gasprice
            : gasForSwap * defaultGasPrice;

        console.log('this is gas for swap', gasForSwap);
        console.log('this is gas price', tx.gasprice);

        require(
            params.toNativePath[params.toNativePath.length - 1] ==
                params.tokenIn,
            'Fees should be collected in tokenIn'
        );
        require(
            params.toNativePath[0] == WrappedNative,
            'Fees should be collected according to WrappedNative price'
        );

        console.log('GETTING THE SWAPPED IN AMOUNT');
        console.logBytes(
            _encodePathV3(params.toNativePath, params.toNativeFees)
        );
        swappedIn = quoter.quoteExactOutput(
            _encodePathV3(params.toNativePath, params.toNativeFees),
            uniswapFees
        );

        console.log('THIS IS SWAPPED IN -> ', swappedIn);

        require(swappedIn < params.amountIn, 'Swap amount is too low');

        //do the desired swap
        if (params.path.length == 0) {
            ISwapRouter.ExactInputSingleParams memory paramsIn = ISwapRouter
                .ExactInputSingleParams({
                    tokenIn: params.tokenIn,
                    tokenOut: params.tokenOut,
                    fee: feeTier,
                    recipient: params.isTokenOutNative
                        ? address(this)
                        : params.userAddress,
                    deadline: block.timestamp,
                    amountIn: params.amountIn - swappedIn,
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: 0
                });
            amountOut = swapRouter.exactInputSingle(paramsIn);
        } else {
            ISwapRouter.ExactInputParams memory paramsIn = ISwapRouter
                .ExactInputParams({
                    path: _encodePathV3(params.path, params.fees),
                    recipient: params.isTokenOutNative
                        ? address(this)
                        : params.userAddress,
                    deadline: block.timestamp,
                    amountIn: params.amountIn - swappedIn,
                    amountOutMinimum: 0
                });
            amountOut = swapRouter.exactInput(paramsIn);
        }

        if (params.isTokenOutNative) {
            WrappedToken wrappedToken = WrappedToken(WrappedNative);
            wrappedToken.withdraw(amountOut);
            (bool success, ) = payable(params.userAddress).call{
                value: amountOut
            }('');
            require(success);
        }

        return amountOut;
    }

    function approveWithoutFees(
        ApproveWithoutFeesParams memory params
    ) external {
        bytes32 digest = keccak256(
            abi.encodePacked(
                '\x19\x01',
                DOMAIN_SEPARATOR,
                keccak256(
                    abi.encode(
                        GASLESS_APPROVAL_TYPEHASH,
                        params.userAddress,
                        params.tokenAddress,
                        params.approvalValue,
                        params.approvalDeadline,
                        keccak256(abi.encodePacked(params.toNativePath)),
                        keccak256(abi.encodePacked(params.toNativeFees)),
                        params.gasForApproval,
                        params.nonce
                    )
                )
            )
        );
        require(
            params.userAddress ==
                ecrecover(digest, params.sigV, params.sigR, params.sigS),
            '[APROVE WITHOUT FEES] Invalid signature'
        );
        require(
            params.nonce == approvalNonces[params.userAddress]++,
            '[APROVE WITHOUT FEES] Invalid nonce'
        );

        require(
            params.tokenAddress ==
                params.toNativePath[params.toNativePath.length - 1],
            'Path must be for the token address'
        );

        uint approvalFees = tx.gasprice > 0
            ? gasForApproval * tx.gasprice
            : gasForApproval * defaultGasPrice;

        console.log('this is approvalFees: ', approvalFees);
        uint fees = quoter.quoteExactOutput(
            _encodePathV3(params.toNativePath, params.toNativeFees),
            gasForApproval
        );

        console.log('Fees: ', fees);
        ERC20Permit token = ERC20Permit(params.tokenAddress);
        token.permit(
            params.userAddress,
            address(this),
            params.approvalValue,
            params.approvalDeadline,
            params.approvalSigV,
            params.approvalSigR,
            params.approvalSigS
        );
        require(
            token.transferFrom(params.userAddress, address(this), fees),
            '[APPROVE WITHOUT FEES] Failed to transfer from'
        );
    }

    function _verifyDigest(
        bytes32 digest,
        address userAddress,
        bytes32 sigR,
        bytes32 sigS,
        uint8 sigV,
        uint nonce
    ) internal {
        require(
            userAddress == ecrecover(digest, sigV, sigR, sigS),
            '[SWAP WITHOUT FEES] Invalid signature'
        );
        require(
            nonce == nonces[userAddress]++,
            '[SWAP WITHOUT FEES] Invalid nonce'
        );
    }

    function _getDigest(
        uint amountIn,
        address tokenIn,
        address tokenOut,
        address userAddress,
        address[] memory path,
        uint24[] memory fees,
        uint nonce,
        bool isTokenOutNative
    ) internal view returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    '\x19\x01',
                    DOMAIN_SEPARATOR,
                    keccak256(
                        abi.encode(
                            GASLESS_SWAP_TYPEHASH,
                            amountIn,
                            tokenIn,
                            tokenOut,
                            userAddress,
                            keccak256(abi.encodePacked(path)),
                            keccak256(abi.encodePacked(fees)),
                            nonce,
                            isTokenOutNative
                        )
                    )
                )
            );
    }

    function _encodePathV3(
        address[] memory _path,
        uint24[] memory _fees
    ) internal pure returns (bytes memory path) {
        path = abi.encodePacked(_path[0]);
        for (uint i = 0; i < _fees.length; i++) {
            path = abi.encodePacked(path, _fees[i], _path[i + 1]);
        }
    }

    function getChainId() internal view returns (uint256) {
        uint256 id;
        assembly {
            id := chainid()
        }
        return id;
    }

    receive() external payable {}
}

