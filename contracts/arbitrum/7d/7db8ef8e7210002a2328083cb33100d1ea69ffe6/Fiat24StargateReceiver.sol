// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;
pragma abicoder v2;

import "./Initializable.sol";
import "./AccessControlUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./SafeMath.sol";
import "./SafeERC20Upgradeable.sol";
import "./IERC20Upgradeable.sol";
import "./ISwapRouter.sol";
import "./IPeripheryPaymentsWithFee.sol";
import "./IQuoter.sol";
import "./TransferHelper.sol";
import "./IStargateReceiver.sol";
import "./IStargateWidget.sol";
import "./IStargateEthVault.sol";
import "./IFiat24Account.sol";
import "./IFiat24Token.sol";
import "./ISanctionsList.sol";

error Fiat24StargateReceiver__NotOperator(address sender);
error Fiat24StargateReceiver__Paused();
error Fiat24StargateReceiver__NotStargateRouter(address sender);
error Fiat24StargateReceiver__EthTransferFailed();
error Fiat24StargateReceiver__NotValidOutputToken(address token);


contract Fiat24StargateReceiver is IStargateReceiver, Initializable, AccessControlUpgradeable, PausableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeMath for uint256;

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    uint256 public constant STATUS_LIVE = 5;
    uint256 public constant CRYPTO_DESK = 9105;
    uint256 public constant SUNDRY = 9103;
    uint256 public constant PL = 9203;
    uint256 public constant CIRCLE = 80000;
    uint256 public constant FOURDECIMALS = 10000;

    address public constant UNISWAP_FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address public constant UNISWAP_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address public constant UNISWAP_PERIPHERY_PAYMENTS = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address public constant UNISWAP_QUOTER = 0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6;

    bool public constant SANCTION_CHECK = true;
    address public constant SANCTION_CHECK_CONTRACT = 0x40C57923924B5c5c5455c48D93317139ADDaC8fb;

    address public weth_address;
    address public usd24_address;
    address public usdc_address;
    address public stargateRouter;
    address public stargateEthVault;
    address public fiat24Account;
    uint24 public fee;
    uint24 public fiat24PoolFee;
    uint256 public fiat24PoolSlippage;
    uint24 public eth_usdc_PoolFee;
    uint256 public eth_usdc_PoolSlippage;

    mapping (address => bool) public validOutputTokens;

    event ReceivedOnDestination(address indexed token, address indexed fiat24token, uint256 amount);
    event UnsupportedTokenToTopUp(address indexed token, address indexed toAddress, uint256 amount);
    event UniswapFailed(address indexed token, address indexed toAddress, uint256 amount);
    event TokenReceivedAndSwapped(address indexed token, address indexed toAddress, uint256 amount);
    event TokenReceivedAndSent(address indexed token, address indexed toAddress, uint256 amount);
    event TokenTransferNotAllowed(uint256 indexed tokenId, address indexed toAddress, uint256 amount);
    event AddressSanctioned(address indexed toAddress);

    function initialize(
        address _stargageRouter, 
        address _stargateEthValue, 
        address _weth_address, 
        address _usd24_address,
        address _usdc_address,
        address _fiat24Account, 
        uint24 _fee,
        uint24 _fiat24PoolFee,
        uint256 _fiat24PoolSlippage,
        uint24 _eth_usdc_PoolFee,
        uint256 _eth_usdc_PoolSlippage,
        address[] memory _validOutputTokens
    ) public initializer {
        __Context_init_unchained();
        __AccessControl_init_unchained();
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(OPERATOR_ROLE, _msgSender());
        stargateRouter = _stargageRouter;
        stargateEthVault = _stargateEthValue;
        weth_address = _weth_address;
        usd24_address = _usd24_address;
        usdc_address = _usdc_address;
        fiat24Account = _fiat24Account;
        fee = _fee;
        fiat24PoolFee = _fiat24PoolFee;
        fiat24PoolSlippage = _fiat24PoolSlippage;
        eth_usdc_PoolFee = _eth_usdc_PoolFee;
        eth_usdc_PoolSlippage = _eth_usdc_PoolSlippage;
        for(uint i; i < _validOutputTokens.length; i++) {
            validOutputTokens[_validOutputTokens[i]] = true;
        }
    }

    function sgReceive(uint16 /*_chainId*/, bytes memory /*_srcAddress*/, uint /*_nonce*/, address _token, uint _amountLD, bytes memory _payload) override external {
        if(msg.sender !=  address(stargateRouter)) revert Fiat24StargateReceiver__NotStargateRouter(_msgSender());
        if(paused()) revert Fiat24StargateReceiver__Paused();
        (address _toAddr, address _outputToken) = abi.decode(_payload, (address, address));
        if(!validOutputTokens[_outputToken]) revert Fiat24StargateReceiver__NotValidOutputToken(_outputToken);
        
        uint256 tokenId = getTokenByAddress(_toAddr);
        if(_token == stargateEthVault) {
            receiveETH(tokenId, _toAddr, _outputToken, _amountLD);
        } else if(_token == usdc_address) {
            receiveERC20(tokenId, _token, _amountLD, _toAddr, _outputToken);
        } else {
            IERC20Upgradeable(_token).safeTransfer(IFiat24Account(fiat24Account).ownerOf(SUNDRY), _amountLD);
            emit UnsupportedTokenToTopUp(_token, _toAddr, _amountLD);
        }
        emit ReceivedOnDestination(_token, _outputToken, _amountLD);
    }

    function receiveERC20(uint256 _tokenId, address _token, uint _amountLD, address _toAddr, address _outputToken) internal {
        IERC20Upgradeable(_token).safeTransfer(IFiat24Account(fiat24Account).ownerOf(CRYPTO_DESK), _amountLD);
        uint256 usd24Amount = _amountLD.div(FOURDECIMALS);
        uint256 usd24FeeAmount = getFeeAmount(usd24Amount);
        IERC20Upgradeable(usd24_address).safeTransferFrom(IFiat24Account(fiat24Account).ownerOf(CRYPTO_DESK), address(this), usd24Amount);
        if(SANCTION_CHECK) {
            ISanctionsList sanctionsList = ISanctionsList(SANCTION_CHECK_CONTRACT);
            if(sanctionsList.isSanctioned(_msgSender())) {
                IERC20Upgradeable(usd24_address).safeTransfer(IFiat24Account(fiat24Account).ownerOf(SUNDRY), usd24Amount);
                emit AddressSanctioned(_msgSender());
            }
        }
        if( _tokenId == 0 || 
            IFiat24Account(fiat24Account).status(_tokenId) != STATUS_LIVE ||
            !IFiat24Token(usd24_address).tokenTransferAllowed(address(this), address(_toAddr), usd24Amount-usd24FeeAmount)) {
            IERC20Upgradeable(usd24_address).safeTransfer(IFiat24Account(fiat24Account).ownerOf(SUNDRY), usd24Amount);
            emit TokenTransferNotAllowed(_tokenId, _toAddr, usd24Amount);
        } else {
            if(_outputToken == usd24_address) {
                IERC20Upgradeable(usd24_address).safeTransfer(_toAddr, usd24Amount-usd24FeeAmount);
                IERC20Upgradeable(usd24_address).safeTransfer(IFiat24Account(fiat24Account).ownerOf(PL), usd24FeeAmount);
                emit TokenReceivedAndSent(_outputToken, _toAddr, usd24Amount-usd24FeeAmount);
            } else {
                uint256 amountOutMininum = getQuote(usd24_address, _outputToken, fiat24PoolFee, usd24Amount-usd24FeeAmount);
                TransferHelper.safeApprove(usd24_address, address(UNISWAP_ROUTER), usd24Amount-usd24FeeAmount);
                ISwapRouter.ExactInputSingleParams memory params =
                    ISwapRouter.ExactInputSingleParams({
                        tokenIn: usd24_address,
                        tokenOut: _outputToken,
                        fee: fiat24PoolFee,
                        recipient: address(this),
                        deadline: block.timestamp + 15,
                        amountIn: usd24Amount-usd24FeeAmount,
                        amountOutMinimum: amountOutMininum.sub(amountOutMininum.mul(fiat24PoolSlippage).div(100)),
                        sqrtPriceLimitX96: 0
                    });
                uint256 outputAmount = ISwapRouter(UNISWAP_ROUTER).exactInputSingle(params);
                if(outputAmount == 0) {
                    IERC20Upgradeable(usd24_address).safeTransfer(IFiat24Account(fiat24Account).ownerOf(SUNDRY), usd24Amount-usd24FeeAmount);
                    emit UniswapFailed(usd24_address, _toAddr, usd24Amount-usd24FeeAmount);
                } else {
                    IERC20Upgradeable(_outputToken).transfer(_toAddr, outputAmount);
                    IERC20Upgradeable(usd24_address).safeTransfer(IFiat24Account(fiat24Account).ownerOf(PL), usd24FeeAmount);
                    emit TokenReceivedAndSwapped(_outputToken, _toAddr, outputAmount);
                }
            }
        }  
    }

    function receiveETH(uint256 _tokenId, address _toAddr, address _outputToken, uint256 _amountLD) internal {
        // uint256 ethAmount = IStargateEthVault(stargateEthVault).balanceOf(_toAddr);
        // IStargateEthVault(stargateEthVault).withdraw(IStargateEthVault(stargateEthVault).balanceOf(_toAddr));
        uint256 amountOutMininumETH = getQuote(weth_address, usdc_address, eth_usdc_PoolFee, _amountLD);
        ISwapRouter.ExactInputSingleParams memory paramsEthToUsdc =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: weth_address,
                tokenOut: usdc_address,
                fee: eth_usdc_PoolFee,
                recipient: address(this),
                deadline: block.timestamp + 15,
                amountIn: _amountLD,
                amountOutMinimum: amountOutMininumETH.sub(amountOutMininumETH.mul(eth_usdc_PoolSlippage).div(100)),
                sqrtPriceLimitX96: 0
            });
        uint256 outputAmountUsdc = ISwapRouter(UNISWAP_ROUTER).exactInputSingle{value: _amountLD}(paramsEthToUsdc);
        IPeripheryPaymentsWithFee(UNISWAP_PERIPHERY_PAYMENTS).refundETH();
        if(outputAmountUsdc == 0) {
            (bool sent,) = IFiat24Account(fiat24Account).ownerOf(SUNDRY).call{value: _amountLD}("");
            emit UniswapFailed(weth_address, _toAddr, _amountLD);
            if(!sent) revert Fiat24StargateReceiver__EthTransferFailed();
        } else {
            IERC20Upgradeable(usdc_address).safeTransfer(IFiat24Account(fiat24Account).ownerOf(CRYPTO_DESK), outputAmountUsdc);
            uint256 usd24Amount = outputAmountUsdc.div(FOURDECIMALS);
            uint256 usd24FeeAmount = getFeeAmount(usd24Amount);
            IERC20Upgradeable(usd24_address).safeTransferFrom(IFiat24Account(fiat24Account).ownerOf(CRYPTO_DESK), address(this), usd24Amount);
            if(SANCTION_CHECK) {
                ISanctionsList sanctionsList = ISanctionsList(SANCTION_CHECK_CONTRACT);
                if(sanctionsList.isSanctioned(_msgSender())) {
                    IERC20Upgradeable(usd24_address).safeTransfer(IFiat24Account(fiat24Account).ownerOf(SUNDRY), usd24Amount);
                    emit AddressSanctioned(_msgSender());
                }
            }
            if( _tokenId == 0 || 
                IFiat24Account(fiat24Account).status(_tokenId) != STATUS_LIVE ||
                !IFiat24Token(usd24_address).tokenTransferAllowed(address(this), address(_toAddr), usd24Amount-usd24FeeAmount)) {
                IERC20Upgradeable(usd24_address).safeTransfer(IFiat24Account(fiat24Account).ownerOf(SUNDRY), usd24Amount);
                emit TokenTransferNotAllowed(_tokenId, _toAddr, usd24Amount);
            } else {
                if(_outputToken == usd24_address) {
                    IERC20Upgradeable(usd24_address).safeTransfer(_toAddr, usd24Amount-usd24FeeAmount);
                    IERC20Upgradeable(usd24_address).safeTransfer(IFiat24Account(fiat24Account).ownerOf(PL), usd24FeeAmount);
                    emit TokenReceivedAndSent(_outputToken, _toAddr, usd24Amount-usd24FeeAmount);
                } else {
                    uint256 amountOutMininum = getQuote(usd24_address, _outputToken, fiat24PoolFee, usd24Amount-usd24FeeAmount);
                    TransferHelper.safeApprove(usd24_address, address(UNISWAP_ROUTER), usd24Amount-usd24FeeAmount);
                    ISwapRouter.ExactInputSingleParams memory params =
                        ISwapRouter.ExactInputSingleParams({
                            tokenIn: usd24_address,
                            tokenOut: _outputToken,
                            fee: fiat24PoolFee,
                            recipient: address(this),
                            deadline: block.timestamp + 15,
                            amountIn: usd24Amount-usd24FeeAmount,
                            amountOutMinimum: amountOutMininum.sub(amountOutMininum.mul(fiat24PoolSlippage).div(100)),
                            sqrtPriceLimitX96: 0
                        });
                    uint256 outputAmount = ISwapRouter(UNISWAP_ROUTER).exactInputSingle(params);
                    if(outputAmount == 0) {
                        IERC20Upgradeable(usd24_address).safeTransfer(IFiat24Account(fiat24Account).ownerOf(SUNDRY), usd24Amount-usd24FeeAmount);
                        emit UniswapFailed(usd24_address, _toAddr, usd24Amount-usd24FeeAmount);
                    } else {
                        IERC20Upgradeable(_outputToken).transfer(_toAddr, outputAmount);
                        IERC20Upgradeable(usd24_address).safeTransferFrom(IFiat24Account(fiat24Account).ownerOf(CRYPTO_DESK), IFiat24Account(fiat24Account).ownerOf(PL), usd24FeeAmount);
                        emit TokenReceivedAndSwapped(_outputToken, _toAddr, outputAmount);
                    }
                }
            }  
        }
    }

    function getFeeAmount(uint256 _usdcAmount) public view returns(uint256) {
        return _usdcAmount.mul(fee).div(100);
    }

    function getTokenByAddress(address owner) public view returns(uint256) {
        try IFiat24Account(fiat24Account).tokenOfOwnerByIndex(owner, 0) returns(uint256 tokenid) {
            return tokenid;
        } catch Error(string memory) {
            return IFiat24Account(fiat24Account).historicOwnership(owner);
        } catch (bytes memory) {
            return IFiat24Account(fiat24Account).historicOwnership(owner);
        }
    }

    function getQuote(address tokenIn, address tokenOut, uint24 fee_, uint256 amount) public payable returns(uint256) {
        return IQuoter(UNISWAP_QUOTER).quoteExactInputSingle(
            tokenIn,
            tokenOut,
            fee_,
            amount,
            0
        ); 
    }

    function pause() external {
        if(!hasRole(OPERATOR_ROLE, msg.sender)) revert Fiat24StargateReceiver__NotOperator(_msgSender());
        _pause();
    }

    receive() external payable {}
}
