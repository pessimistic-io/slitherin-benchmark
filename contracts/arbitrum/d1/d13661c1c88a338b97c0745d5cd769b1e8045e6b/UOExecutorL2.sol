// SPDX-License-Identifier: GLP-v3.0

pragma solidity ^0.8.4;

import "./GnosisSafeStorage.sol";
import "./SafeERC20.sol";
import "./IL2_AmmWrapper.sol";
import "./IWETH.sol";
import "./ISwapRouter.sol";
import "./BytesLib.sol";
import "./IAvaultForAave.sol";
import "./AVaultForAaveFactory.sol";
import "./IAddressesProvider.sol";

// this is used as the library of User's Safe
// every method of this contract must be safe
contract UOExecutorL2 is GnosisSafeStorage{
    using SafeERC20 for IERC20;
    using BytesLib for bytes;

    IWETH public immutable weth;
    ISwapRouter public immutable uniRouter;
    AVaultForAaveFactory public immutable avaultAaveFactory;
    IAddressesProvider public immutable iAddressesProvider;

    address internal constant SENTINEL_OWNERS = address(0x1);
    uint private constant L1CHAINID = 1;
    uint256 private constant ADDR_SIZE = 20;
    uint private constant UNISWAP_MIN_OUTPUT = 100000; // refer to 0.1USDC

    event WITHDRAW_FROM_WALLET(address _token, uint _amount, address _bridgeToken, uint _destChainId, address indexed _destAddress, uint _bonderFee);
    event DEPOSIT_TO_AVAULT(address _srcToken, uint _amount, address _targetToken, uint _targetTokenAmount);
    event WITHDRAW_FROM_AVAULT(address _token, uint _shareAmount);

    constructor(IWETH _weth, ISwapRouter _uniRouter, AVaultForAaveFactory _avaultAaveFactory, IAddressesProvider _IAddressesProvider){
        weth = _weth;
        uniRouter = _uniRouter;
        avaultAaveFactory = _avaultAaveFactory;
        iAddressesProvider = _IAddressesProvider;
    }

    receive() external payable {}

    /**
    * @param _bonderFee: refer to https://docs.hop.exchange/js-sdk/getting-started#estimate-total-bonder-fee
    *  if the _destChainId == currentChain, then no need to set _bonderFee
    **/
    function withdrawFromWallet(bytes memory _path, uint _amount, uint _destChainId, address _destAddress, uint _bonderFee) public{
        address _token = _path.toAddress(0);
        address _bridgeToken = _path.toAddress(_path.length - ADDR_SIZE);
        
        require(isOwner(_destAddress), "to owner only");

        uint _balanceOfERC20 = IERC20(_token).balanceOf(address(this));
        if(_token == address(weth) && _balanceOfERC20 < _amount && address(this).balance > 0){
            weth.deposit{value: (address(this).balance)}();
            _balanceOfERC20 = IERC20(_token).balanceOf(address(this));
        }
        require(_balanceOfERC20 > 0, "0 amount");

        uint _bridgeTokenAmount = _balanceOfERC20;
        if(_token != _bridgeToken){
            IERC20(_token).safeIncreaseAllowance(address(uniRouter), _balanceOfERC20);
            _bridgeTokenAmount = uniRouter.exactInput(ISwapRouter.ExactInputParams(_path, address(this), block.timestamp + 100, _balanceOfERC20, UNISWAP_MIN_OUTPUT));
        }

        if(_destChainId == getChainId()){
            //no need to cross chain
            IERC20(_bridgeToken).safeTransfer(_destAddress, _bridgeTokenAmount);
        }else{
            IL2_AmmWrapper _bridge = IL2_AmmWrapper(iAddressesProvider.hopBridge(_bridgeToken));
            require(address(_bridge) != address(0), "invalid bridgeToken");

            require(_bridgeTokenAmount > _bonderFee, "bridge <= bonder fee");
            IERC20(_bridgeToken).safeIncreaseAllowance(address(_bridge), _bridgeTokenAmount);
            /** 
            * @dev A bonder fee is required when sending L2->L2 or L2->L1. There is no bonder fee when sending L1->L2.
            * Do not set destinationAmountOutMin and destinationDeadline when sending to L1 because there is no AMM on L1.
            */
            if(_destChainId == L1CHAINID){
                _bridge.swapAndSend(_destChainId, _destAddress, _bridgeTokenAmount, _bonderFee, _bridgeTokenAmount * 98 / 100, block.timestamp + 100, 0, 0);
            }else{
                _bridge.swapAndSend(_destChainId, _destAddress, _bridgeTokenAmount, _bonderFee, _bridgeTokenAmount * 98 / 100, block.timestamp + 100, (_bridgeTokenAmount - _bonderFee) * 98 / 100, block.timestamp + (60 * 60 * 48));
            }
        }

        emit WITHDRAW_FROM_WALLET(_token, _amount, _bridgeToken, _destChainId, _destAddress, _bonderFee);
    }

    function depositToAVault(bytes memory _path, uint _amount) external{
        address _token = _path.toAddress(0);
        address _targetToken = _path.toAddress(_path.length - ADDR_SIZE);

        //convert from ETH to WETH if WETH not enough
        uint _balanceOfERC20 = IERC20(_token).balanceOf(address(this));
        if(_token == address(weth) && _balanceOfERC20 < _amount && address(this).balance > 0){
            weth.deposit{value: (address(this).balance)}();
            _balanceOfERC20 = IERC20(_token).balanceOf(address(this));
        }
        require(_balanceOfERC20 > 0, "0 amount");

        uint _targetTokenAmount = _balanceOfERC20;
        if(_token != _targetToken){
            IERC20(_token).safeIncreaseAllowance(address(uniRouter), _balanceOfERC20);
            _targetTokenAmount = uniRouter.exactInput(ISwapRouter.ExactInputParams(_path, address(this), block.timestamp + 100, _balanceOfERC20, UNISWAP_MIN_OUTPUT));
        }

        address _avaultAave = avaultAaveFactory.tokenToVault(_targetToken);
        require(_avaultAave != address(0), "can't find an AVault");
        IERC20(_targetToken).safeIncreaseAllowance(_avaultAave, _targetTokenAmount);
        IAvaultForAave(_avaultAave).deposit(address(this), _targetTokenAmount);

        emit DEPOSIT_TO_AVAULT(_token, _amount, _targetToken, _targetTokenAmount);
    }

    /**
    * @param _bonderFee: refer to https://docs.hop.exchange/js-sdk/getting-started#estimate-total-bonder-fee
    *  if the _destChainId == currentChain, then no need to set _bonderFee
    **/
    function withdrawFromAVault(bytes memory _path, uint _shareAmount, uint _destChainId, address _destAddress, uint _bonderFee) external{
        address _token = _path.toAddress(0);

        address _avaultAave = avaultAaveFactory.tokenToVault(_token);
        require(_avaultAave != address(0), "can't find an AVault");

        uint _maxShareAmount = IERC20(_avaultAave).balanceOf(address(this));
        uint _finalAmount = _shareAmount < _maxShareAmount ? _shareAmount : _maxShareAmount;
        require(_finalAmount > 0, "0 amount");
        uint _withdrawnAmount = IAvaultForAave(_avaultAave).withdraw(address(this), _finalAmount);

        withdrawFromWallet(_path, _withdrawnAmount, _destChainId, _destAddress, _bonderFee);

        emit WITHDRAW_FROM_AVAULT(_token, _shareAmount);
    }

    function isOwner(address owner) internal view returns (bool) {
        return owner != SENTINEL_OWNERS && owners[owner] != address(0);
    }

    /// @dev Returns the chain id used by this contract.
    function getChainId() public view returns (uint256) {
        uint256 id;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            id := chainid()
        }
        return id;
    }
}
