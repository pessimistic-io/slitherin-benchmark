// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./SafeMath.sol";
import "./Address.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";
import "./Ownable.sol";
import "./EnumerableSet.sol";
import "./EnumerableValues.sol";
import "./IElpManager.sol";
import "./IRouter.sol";
import "./IWETH.sol";
import "./IVault.sol";
import "./IRewardRouter.sol";
import "./IRewardTracker.sol";

interface ISwapRouter {
    struct ExactInputSingleParams {
            address tokenIn;
            address tokenOut;
            uint24 fee;
            address recipient;
            uint256 deadline;
            uint256 amountIn;
            uint256 amountOutMinimum;
            uint160 sqrtPriceLimitX96;
        }

    function exactInputSingle(ExactInputSingleParams memory params) external returns (uint256 amountOut);
    // function exactInput(ExactInputParams memory params) external returns (uint256 amountOut);
    // https://docs.uniswap.org/contracts/v3/reference/periphery/interfaces/ISwapRouter
}



interface ICamelot {
    struct inputToken {
        address tokenAddress;
        uint256 amountIn;
        address receiver;
        bytes permit;
    }
    struct outputToken {
        address tokenAddress;
        uint256 relativeValue;
        address receiver;
    }

    // For : camelot
    function addLiquidity(address tokenA, address tokenB,uint256 amountADesired,uint256 amountBDesired,uint256 amountAMin,uint256 amountBMin,address to,uint256 deadline) external ;
    function removeLiquidity(address tokenA,address tokenB,uint liquidity,uint amountAMin,uint amountBMin,address to,uint deadline
        ) external returns (uint , uint, uint);
    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
        ) external payable returns (uint amountToken, uint amountETH, uint liquidity);

    function removeLiquidityETH(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external returns (uint amountToken, uint amountETH);

        
    function swapExactTokensForETHSupportingFeeOnTransferTokens(uint amountIn, uint amountOutMin, address[] calldata path,address to, address referrer,uint deadline) external payable;
    function swapExactETHForTokensSupportingFeeOnTransferTokens(uint amountOutMin, address[] calldata path, address to, address referrer, uint deadline) external payable;
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(uint amountIn, uint amountOutMin, address[] calldata path, address to, address referrer, uint deadline) external;
}


interface ILPYield {
    function stake(address _token, uint256 _amount) external;
    function unstake(uint256 _amount) external;
    function claim() external;
}



contract Treasury is Ownable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableValues for EnumerableSet.AddressSet;
    using Address for address payable;


    mapping(string => address) public addDef;
    mapping(address => address) public elpToElpManager;
    mapping(address => address) public elpToElpTracker;

    //distribute setting
    EnumerableSet.AddressSet supportedToken;
    uint256[] public weights;
    uint256 public weight_sum;
    bool public openForPublic = true;
    mapping (address => bool) public isHandler;

    receive() external payable {
        // require(msg.sender == weth, "invalid sender");
    }
    
    modifier onlyHandler() {
        require(isHandler[msg.sender] || msg.sender == owner() || openForPublic, "forbidden");
        _;
    }
    
    function setHandler(address _handler, bool _isActive) external onlyOwner {
        isHandler[_handler] = _isActive;
    }
    function approve(address _token, address _spender, uint256 _amount) external onlyOwner {
        IERC20(_token).approve(_spender, _amount);
    }

    function setOpenstate(bool _state) external onlyOwner {
        openForPublic = _state;
    }
    function setWeights(uint256[] memory _weights) external onlyOwner {
        weight_sum = 0;
        weights = _weights;
        for(uint i = 0; i < _weights.length; i++){
            weight_sum = weight_sum.add(_weights[i]);
        }
    }
    function setRelContract(address[] memory _elp_n, address[] memory _elp_manager, address[] memory _elp_tracker) external onlyOwner{
        for(uint i = 0; i < _elp_n.length; i++){
            if (!supportedToken.contains(_elp_n[i]))
                supportedToken.add(_elp_n[i]);    
            elpToElpManager[_elp_n[i]] = _elp_manager[i];
            elpToElpTracker[_elp_n[i]] = _elp_tracker[i];
        }
    }


    function setToken(address[] memory _tokens, bool _state) external onlyOwner{
        if (_state){
            for(uint i = 0; i < _tokens.length; i++){
                if (!supportedToken.contains(_tokens[i]))
                    supportedToken.add(_tokens[i]);
            }
        }
        else{
            for(uint i = 0; i < _tokens.length; i++){
                if (supportedToken.contains(_tokens[i]))
                    supportedToken.remove(_tokens[i]);
            }
        }
    }

    function setAddress(string[] memory _name_list, address[] memory _contract_list) external onlyOwner{
        for(uint i = 0; i < _contract_list.length; i++){
            addDef[_name_list[i]] = _contract_list[i];
        }
    }

    function withdrawToken(address _token, uint256 _amount, address _dest) external onlyOwner {
        IERC20(_token).safeTransfer(_dest, _amount);
    }

    function depositNative(uint256 _amount) external payable onlyOwner {
        uint256 _curBalance = address(this).balance;
        IWETH(addDef["nativeToken"]).deposit{value: _amount > _curBalance ? _curBalance : _amount}();
    }

    function _internalSwap(address _token_src, address _token_dst, uint256 _amount_in, uint256 _amount_out_min) internal returns (uint256) {
        require(_token_src != _token_dst, "src token equals to dst token");
        require(isSupportedToken(_token_src), "not supported src token");
        require(isSupportedToken(_token_dst), "not supported dst token");
        require(addDef["camelotSwap"] != address(0), "camelotSwap contract not set");
        
        uint256 _deadline = block.timestamp.add(1);
        uint256 _src_pre_balance = _token_src == address(0) ? address(this).balance : IERC20(_token_src).balanceOf(address(this));
        uint256 _dst_pre_balance = _token_dst == address(0) ? address(this).balance : IERC20(_token_dst).balanceOf(address(this));
        address referrer = address(0);
        address[] memory _path = new address[](2);
        if (_token_src == address(0)){ //swap with native token
            _path[0] = addDef["nativeToken"];
            _path[1] = _token_dst;
            ICamelot(addDef["camelotSwap"]).swapExactETHForTokensSupportingFeeOnTransferTokens{value:_amount_in}(_amount_out_min,_path, address(this), referrer, _deadline);       
            // swapExactETHForTokensSupportingFeeOnTransferTokens(uint amountOutMin, address[] calldata path, address to, address referrer, uint deadline) external;
        }
        else if (_token_dst == address(0)){ //swap with native token
            _path[0] = _token_src;
            _path[1] = addDef["nativeToken"];
            IERC20(_token_src).approve(addDef["camelotSwap"], _amount_in);
            ICamelot(addDef["camelotSwap"]).swapExactTokensForETHSupportingFeeOnTransferTokens(_amount_in, _amount_out_min, _path, address(this), referrer, _deadline);       
            // swapExactTokensForETHSupportingFeeOnTransferTokens(uint amountIn, uint amountOutMin, address[] calldata path, address to, address referrer,uint deadline) external;
        }
        else{
            _path[0] = _token_src;
            _path[1] = _token_dst;
            IERC20(_token_src).approve(addDef["camelotSwap"], _amount_in);
            ICamelot(addDef["camelotSwap"]).swapExactTokensForTokensSupportingFeeOnTransferTokens(_amount_in, _amount_out_min, _path, address(this), referrer, _deadline);       
            // swapExactTokensForTokensSupportingFeeOnTransferTokens(uint amountIn, uint amountOutMin, address[] calldata path, address to, address referrer, uint deadline) external;
        }
        uint256 _src_cur_balance = _token_src == address(0) ? address(this).balance : IERC20(_token_src).balanceOf(address(this));
        uint256 _dst_cur_balance = _token_dst == address(0) ? address(this).balance : IERC20(_token_dst).balanceOf(address(this));
        require(_src_pre_balance.sub(_src_cur_balance) <= _amount_in, "src token decrease not match");
        require(_dst_cur_balance.sub(_dst_pre_balance) >= _amount_out_min, "dst token increase not match");
        return _dst_cur_balance.sub(_dst_pre_balance);
    }


    function treasureSwap(address _src, address _dst, uint256 _amount_in, uint256 _amount_out_min) external onlyHandler returns (uint256) {
        return _internalSwap(_src, _dst, _amount_in, _amount_out_min);
    }


    // ------ Funcs. processing ELP
    function buyELP(address _token, address _elp_n, uint256 _amount) external onlyHandler returns (uint256) {
        require(isSupportedToken(_token), "not supported src token");
        if (_amount == 0)
            _amount = IERC20(_elp_n).balanceOf(address(this));
        return _buyELP(_token, _elp_n, _amount);
    }
    function _buyELP(address _token, address _elp_n, uint256 _amount) internal returns (uint256) {
        require(elpToElpManager[_elp_n]!= address(0), "ELP manager not set");
        uint256 elp_ret = 0;
        if (_token != address(0)){
            IERC20(_token).approve(elpToElpManager[_elp_n], _amount);
            require(IERC20(_token).balanceOf(address(this)) >= _amount, "insufficient token to buy elp");
            elp_ret = IElpManager(elpToElpManager[_elp_n]).addLiquidity(_token, _amount, 0, 0);
        }
        else{
            require(address(this).balance >= _amount, "insufficient native token ");
            elp_ret = IElpManager(elpToElpManager[_elp_n]).addLiquidityETH{value: _amount}();
        }
        return elp_ret;
    }

    function sellELP(address _token_out, address _elp_n, uint256 _amount_sell) external onlyHandler returns (uint256) {
        require(isSupportedToken(_token_out), "not supported out token");
        require(isSupportedToken(_elp_n), "not supported elp n");
        if (_amount_sell == 0){
            _amount_sell = IERC20(_elp_n).balanceOf(address(this));
        }
        return _sellELP(_token_out, _elp_n, _amount_sell);
    }

    function _sellELP(address _token_out, address _elp_n, uint256 _amount_sell) internal returns (uint256) {
        require(isSupportedToken(_token_out), "not supported src token");
        require(elpToElpManager[_elp_n]!= address(0), "ELP manager not set");
        IERC20(_elp_n).approve(elpToElpManager[_elp_n], _amount_sell);
        require(IERC20(_elp_n).balanceOf(address(this)) >= _amount_sell, "insufficient elp to sell");

        uint256 token_ret = 0;
        if (_token_out != address(0)){
            token_ret = IElpManager(elpToElpManager[_elp_n]).removeLiquidity(_token_out, _amount_sell, 0, address(this));
        }
        else{
            token_ret = IElpManager(elpToElpManager[_elp_n]).removeLiquidityETH(_amount_sell);
        }
        return token_ret;
    }

    function stakeELP(address _elp_n, uint256 _amount)  external onlyHandler returns (uint256) {
        require(isSupportedToken(_elp_n), "not supported elp n");
        if (_amount == 0){
            _amount = IERC20(_elp_n).balanceOf(address(this));
        }       
        return _stakeELP(_elp_n, _amount);
    }
    function _stakeELP(address _elp_n, uint256 _amount) internal returns (uint256) {
        require(IERC20(_elp_n).balanceOf(address(this)) >= _amount, "insufficient elp");
        require(isSupportedToken(_elp_n), "not supported elp n");
        require(addDef["RewardRouter"] != address(0), "RewardRouter not set");
        IERC20(_elp_n).approve(elpToElpTracker[_elp_n], _amount);
        return IRewardRouter(addDef["RewardRouter"]).stakeELPn(_elp_n, _amount);
    }

    function _unstakeELP(address _elp_n, uint256 _amount) internal returns (uint256) {
        require(isSupportedToken(_elp_n), "not supported elp n");
        require(addDef["RewardRouter"] != address(0), "RewardRouter not set");
        IERC20(_elp_n).approve(addDef["RewardRouter"], _amount);
        return IRewardRouter(addDef["RewardRouter"]).unstakeELPn(_elp_n, _amount);
    }

    function unstakeELP(address _elp_n, uint256 _amount)  external onlyHandler returns (uint256) {
         require(isSupportedToken(_elp_n), "not supported elp n");
        if (_amount == 0){
            _amount = IERC20(elpToElpTracker[_elp_n]).balanceOf(address(this));
        }     
        return _unstakeELP(_elp_n, _amount);
    }


    function claimELPReward()  external onlyHandler returns (uint256[] memory) {
        return _claimELPReward();
    }

    function _claimELPReward() internal returns (uint256[] memory) {
        require(addDef["RewardRouter"] != address(0), "RewardRouter not set");
        return IRewardRouter(addDef["RewardRouter"]).claimAll();
    }


    function sellEUSD(address _tokenOut, uint256 _amount)  external payable onlyHandler returns (uint256) {
        return _sellEUSD( _tokenOut, _amount);
    }

    function _sellEUSD(address _tokenOut, uint256 _amount) internal returns (uint256) {
        require(addDef["EUSD"] != address(0), "EUSD not defined");
        require(addDef["RewardRouter"] != address(0), "RewardRouter not set");
        require(IERC20(addDef["EUSD"]).balanceOf(address(this)) >= _amount, "insufficient EUSD");
        IERC20(addDef["EUSD"]).approve(addDef["RewardRouter"], _amount);
        return IRewardRouter(addDef["RewardRouter"]).sellEUSD(_tokenOut, _amount);
    }


    function stakeAEde(uint256 _amount)  external onlyHandler {
        _stakeAEde(_amount);
    }
    function unstakeAEde(uint256 _amount)  external payable onlyHandler  {
        _unstakeAEde(_amount);
    }
    function _stakeAEde(uint256 _amount) internal {
        require(addDef["aEdeStakingPool"] != address(0), "aEdeStakingPool not set");
        require(addDef["aEDE"] != address(0), "aEDE not set");
        require(IERC20(addDef["aEDE"]).balanceOf(address(this)) >= _amount, "insufficient aEDE");
        IERC20(addDef["aEDE"]).approve(addDef["aEdeStakingPool"], _amount);
        IRewardTracker(addDef["aEdeStakingPool"]).stake(addDef["aEDE"], _amount);
    }
    function _unstakeAEde(uint256 _amount) internal {
        require(addDef["aEdeStakingPool"] != address(0), "aEdeStakingPool not set");
        require(addDef["aEDE"] != address(0), "aEDE not set");
        IRewardTracker(addDef["RewardRouter"]).unstake(addDef["aEDE"],_amount);
    }
    function claimAEdeReward( )  external payable onlyHandler{
        require(addDef["aEdeStakingPool"] != address(0), "aEdeStakingPool not set");
        IRewardTracker(addDef["RewardRouter"]).claim(address(this));
    }

    //------ Funcs. processing EDE LP
    function addEdeLPNative(uint256 _amount_ede, uint256 _amount_eth) external payable onlyHandler returns (uint amountToken, uint amountETH, uint liquidity) {
        return _addEdeLPNative(_amount_ede, _amount_eth);
    }

    function _addEdeLPNative(uint256 _amount_ede, uint256 _amount_eth) private returns (uint amountToken, uint amountETH, uint liquidity) {
        require(addDef["camelotRouter"] != address(0), "camelot lp contract not defined");
        require(addDef["EDE"] != address(0), "EDE not defined");
        require(IERC20(addDef["EDE"]).balanceOf(address(this)) >= _amount_ede, "insufficient EDE");
        require(address(this).balance >= _amount_eth, "insufficient eth");

        IERC20(addDef["EDE"]).approve(addDef["camelotRouter"], _amount_ede);
        return ICamelot(addDef["camelotRouter"]).addLiquidityETH{value:_amount_eth}(addDef["EDE"], _amount_ede,0,0,address(this), block.timestamp.add(1));
    }


    function removeEdeLPNative(uint256 _amount_lptoken) external payable onlyHandler returns (uint amountToken, uint amountETH) {
        return _removeEdeLPNative(_amount_lptoken);
    }

    function _removeEdeLPNative(uint256 _amount_lptoken) private returns (uint amountToken, uint amountETH) {
        require(addDef["camelotRouter"] != address(0), "camelot lp contract not defined");
        require(addDef["EDE"] != address(0), "EDE not defined");
        require(addDef["edeLpToken"] != address(0), "edeLpToken not defined");
        require(IERC20(addDef["edeLpToken"]).balanceOf(address(this)) >= _amount_lptoken, "insufficient EDE");
        require(address(this).balance >= _amount_lptoken, "insufficient eth");

        IERC20(addDef["edeLpToken"]).approve(addDef["camelotRouter"], _amount_lptoken);
        return ICamelot(addDef["camelotRouter"]).removeLiquidityETH( addDef["edeLpToken"], _amount_lptoken, 0, 0, address(this), block.timestamp.add(1));
    }



    // Func. for public
    // function spendingEUSD(address _token, address _elp) external returns (uint256) {
    //     require(isSupportedToken(_token), "not supported src token");

    //     uint256 eusdBalance = IERC20(EUSD).balanceOf(address(this));
    //     //step1 sell
    //     IERC20(EUSD).approve(RewardRouter, eusdBalance);
    //     uint256 sold_amount = IRewardRouter(RewardRouter).sellEUSD(_token, eusdBalance);

    //     //step2 swap to usingToken
    //     // _swapUV3(_token, Token_lp, sold_amount);

    //     //step3 buy EDE LP
    //     uint256 amounts_buy_LP = sold_amount.mul(weights[0]).div(weight_sum);
    //     _addEdeLPNative(amounts_buy_LP, 0);
    //     //step3.1 stake EDE LP Token

    //     //step.4 buy ELP
    //     uint256 amounts_buy_ELP = sold_amount.sub(amounts_buy_LP);
    //     IElpManager(elpManager[_elp]).addLiquidity(_token, amounts_buy_ELP, 0, 0);
    //     //step 4.1 stake ELP

    //     return 0;
    // }


    // function swap(address _src_token, address _dst_token, uint256 _amount) public returns (uint256) {
    //     require(isSupportedToken(_src_token), "not supported src token");
    //     require(isSupportedToken(_dst_token), "not supported dst token");
    //     IERC20(_src_token).safeTransferFrom(_msgSender(), address(this), _amount);
    //     uint256 orig_dst_balance = IERC20(_dst_token).balanceOf(address(this));
    //     uint256 orig_src_balance = IERC20(_src_token).balanceOf(address(this));
    //     uint256 receive_dst_balance = _swapUV3(_src_token, _dst_token, _amount);
    //     require(IERC20(_src_token).balanceOf(address(this)) >= orig_src_balance, "src token not enough");
    //     require(IERC20(_dst_token).balanceOf(address(this)).sub(orig_dst_balance) >= receive_dst_balance, "not enough receipt");
    //     IERC20(_dst_token).transfer(_msgSender(), receive_dst_balance);
    //     return receive_dst_balance;
    // }
    // function _swapUV3(address _src_token, address _dst_token, uint256 _amount) private returns (uint256) {
    //     ISwapRouter.ExactInputSingleParams memory eisp;
    //     eisp.tokenIn = _src_token;
    //     eisp.tokenOut = _dst_token;
    //     eisp.fee = fee;
    //     eisp.recipient = address(this);
    //     eisp.deadline = block.timestamp.add(2);
    //     eisp.amountIn =  _amount;
    //     return ISwapRouter(univ3).exactInputSingle(eisp) ;
    // }


    // Func. public view
    function isSupportedToken(address _token) public view returns(bool){
        return supportedToken.contains(_token);
    }

}
