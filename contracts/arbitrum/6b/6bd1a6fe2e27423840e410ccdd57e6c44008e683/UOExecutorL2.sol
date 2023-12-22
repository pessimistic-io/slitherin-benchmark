// SPDX-License-Identifier: GLP-v3.0

pragma solidity ^0.8.4;

import "./GnosisSafeStorage.sol";
import "./SafeERC20.sol";
import "./IL2_AmmWrapper.sol";
import "./Ownable.sol";
import "./IWETH.sol";
import "./ISwapRouter.sol";
import "./BytesLib.sol";
import "./IAvaultForAave.sol";
import "./AVaultForAaveFactory.sol";

// this is used as the library of User's Safe
// every method of this contract must be safe
contract UOExecutorL2 is GnosisSafeStorage, Ownable{
    using SafeERC20 for IERC20;
    using BytesLib for bytes;

    mapping(address => address) public hopBridge; //token => L2_AmmWrapper
    IWETH public immutable weth;
    ISwapRouter public immutable uniRouter;
    AVaultForAaveFactory public immutable avaultAaveFactory;

    address internal constant SENTINEL_OWNERS = address(0x1);
    uint private constant L1CHAINID = 1;
    uint256 private constant ADDR_SIZE = 20;
    uint private constant UNISWAP_MIN_OUTPUT = 100000; // refer to 0.1USDC

    event HOPBRIDGE_SET(address indexed _token, address _bridge);
    event WITHDRAW_FROM_WALLET(address _token, uint _amount, address _bridgeToken, uint _destChainId, address indexed _destAddress, uint _bonderFee);
    event DEPOSIT_TO_AVAULT(address _srcToken, uint _amount, address _targetToken, uint _targetTokenAmount);
    event WITHDRAW_FROM_AVAULT(address _token, uint _shareAmount);

    //_bridgeMapping: [token1,bridge1,token2,bridge2,...]
    // arbitrum e.g.
    // hopBridge[0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8] = 0xe22D2beDb3Eca35E6397e0C6D62857094aA26F52; //USDC
    // hopBridge[0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9] = 0xCB0a4177E0A60247C0ad18Be87f8eDfF6DD30283; //USDT
    // hopBridge[0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1] = 0xe7F40BF16AB09f4a6906Ac2CAA4094aD2dA48Cc2; //DAI
    // hopBridge[0x82aF49447D8a07e3bd95BD0d56f35241523fBab1] = 0x33ceb27b39d2Bb7D2e61F7564d3Df29344020417; //WETH
    // hopBridge[0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f] = 0xC08055b634D43F2176d721E26A3428D3b7E7DdB5; //WBTC
    constructor(IWETH _weth, ISwapRouter _uniRouter, AVaultForAaveFactory _avaultAaveFactory,  address[] memory _bridgeMapping){
        uint _counter = _bridgeMapping.length / 2;
        for(uint i = 0; i < _counter; i++){
            hopBridge[_bridgeMapping[i * 2]] = _bridgeMapping[i * 2 + 1];
        }

        weth = _weth;
        uniRouter = _uniRouter;
        avaultAaveFactory = _avaultAaveFactory;
    }

    receive() external payable {}

    /**
    * @param _bonderFee: refer to https://docs.hop.exchange/js-sdk/getting-started#estimate-total-bonder-fee
    **/
    function withdrawFromWallet(bytes memory _path, uint _amount, uint _destChainId, address _destAddress, uint _bonderFee) public payable{
        address _token = _path.toAddress(0);
        address _bridgeToken = _path.toAddress(_path.length - ADDR_SIZE);
        
        IL2_AmmWrapper _bridge = IL2_AmmWrapper(hopBridge[_bridgeToken]);
        require(address(_bridge) != address(0), "invalid bridgeToken");
        require(_amount > 0, "0 amount");
        require(isOwner(_destAddress), "to owner only");

        if(_token == address(weth) && msg.value > 0){
            weth.deposit{value: msg.value}();
        }
        uint _balance = IERC20(_token).balanceOf(address(this));
        uint _finalAmount = _balance > _amount ? _amount : _balance;

        uint _bridgeTokenAmount = _finalAmount;
        if(_token != _bridgeToken){
            IERC20(_token).safeIncreaseAllowance(address(uniRouter), _finalAmount);
            _bridgeTokenAmount = uniRouter.exactInput(ISwapRouter.ExactInputParams(_path, address(this), block.timestamp + 100, _finalAmount, UNISWAP_MIN_OUTPUT));
        }

        require(_bridgeTokenAmount > _bonderFee, "bridge <= bonder fee");
        IERC20(_bridgeToken).safeIncreaseAllowance(address(_bridge), _bridgeTokenAmount);
        /** 
         * @dev A bonder fee is required when sending L2->L2 or L2->L1. There is no bonder fee when sending L1->L2.
         * Do not set destinationAmountOutMin and destinationDeadline when sending to L1 because there is no AMM on L1.
         */
        if(_destChainId == L1CHAINID){
            _bridge.swapAndSend(_destChainId, _destAddress, _bridgeTokenAmount, _bonderFee, _bridgeTokenAmount * 98 / 100, block.number + 10, 0, 0);
        }else{
            _bridge.swapAndSend(_destChainId, _destAddress, _bridgeTokenAmount, _bonderFee, _bridgeTokenAmount * 98 / 100, block.number + 10, (_bridgeTokenAmount - _bonderFee) * 98 / 100, 0);
        }

        emit WITHDRAW_FROM_WALLET(_token, _amount, _bridgeToken, _destChainId, _destAddress, _bonderFee);
    }

    function depositToAVault(bytes memory _path, uint _amount) external payable{
        address _token = _path.toAddress(0);
        address _targetToken = _path.toAddress(_path.length - ADDR_SIZE);

        if(_token == address(weth) && msg.value > 0){
            weth.deposit{value: msg.value}();
        }
        uint _balance = IERC20(_token).balanceOf(address(this));
        uint _finalAmount = _balance > _amount ? _amount : _balance;

        uint _targetTokenAmount = _finalAmount;
        if(_token != _targetToken){
            IERC20(_token).safeIncreaseAllowance(address(uniRouter), _finalAmount);
            _targetTokenAmount = uniRouter.exactInput(ISwapRouter.ExactInputParams(_path, address(this), block.timestamp + 100, _finalAmount, UNISWAP_MIN_OUTPUT));
        }

        address _avaultAave = avaultAaveFactory.tokenToVault(_targetToken);
        require(_avaultAave != address(0), "can't find an AVault");
        IERC20(_targetToken).safeIncreaseAllowance(_avaultAave, _targetTokenAmount);
        IAvaultForAave(_avaultAave).deposit(address(this), _targetTokenAmount);

        emit DEPOSIT_TO_AVAULT(_token, _amount, _targetToken, _targetTokenAmount);
    }

    function withdrawFromAVault(bytes memory _path, uint _shareAmount, uint _destChainId, address _destAddress, uint _bonderFee) external{
        address _token = _path.toAddress(0);
        require(_shareAmount > 0, "0 amount");

        address _avaultAave = avaultAaveFactory.tokenToVault(_token);
        require(_avaultAave != address(0), "can't find an AVault");
        uint _withdrawnAmount = IAvaultForAave(_avaultAave).withdraw(address(this), _shareAmount);

        withdrawFromWallet(_path, _withdrawnAmount, _destChainId, _destAddress, _bonderFee);

        emit WITHDRAW_FROM_AVAULT(_token, _shareAmount);
    }

    function isOwner(address owner) internal view returns (bool) {
        return owner != SENTINEL_OWNERS && owners[owner] != address(0);
    }

    function setHopBridge(address _token, address _bridge) external onlyOwner{
        hopBridge[_token] = _bridge;
        emit HOPBRIDGE_SET(_token, _bridge);
    }
}
