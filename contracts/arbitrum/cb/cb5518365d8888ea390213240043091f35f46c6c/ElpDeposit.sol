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
import "./IWETH.sol";
import "./IElpManager.sol";
import "./IRewardRouter.sol";


interface IElp {
    function burn(address , uint256 _amount) external;
}

contract ElpDeposit is Ownable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableValues for EnumerableSet.AddressSet;
    using Address for address payable;


    mapping(string => address) public addDef;
    mapping(address => address) public elpToElpManager;

    //distribute setting
    EnumerableSet.AddressSet supportedToken;

    mapping (address => bool) public isHandler;
    mapping (address => bool) public isManager;
    uint8 method;

    event SellESUD(address token, uint256 eusd_amount, uint256 token_out_amount);
    event Swap(address token_src, address token_dst, uint256 amount_src, uint256 amount_out);

    receive() external payable {
        // require(msg.sender == weth, "invalid sender");
    }
    
    modifier onlyHandler() {
        require(isHandler[msg.sender] || msg.sender == owner(), "forbidden");
        _;
    }

    function setHandler(address _handler, bool _isActive) external onlyOwner {
        isHandler[_handler] = _isActive;
    }

    function setRelContract(address[] memory _elp_n, address[] memory _elp_manager) external onlyOwner{
        for(uint i = 0; i < _elp_n.length; i++){
            if (!supportedToken.contains(_elp_n[i]))
                supportedToken.add(_elp_n[i]);    
            elpToElpManager[_elp_n[i]] = _elp_manager[i];
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
    
    function sendValue(address payable _receiver, uint256 _amount) external onlyOwner {
        _receiver.sendValue(_amount);
    }

    function redeem(address _token, uint256 _amount, address _dest) external {
        require(isManager[msg.sender], "Only manager");
        require(IERC20(_token).balanceOf(address(this)) >= _amount, "max amount exceed");
        IERC20(_token).safeTransfer(_dest, _amount);
    }

    function depositNative(uint256 _amount) external payable onlyOwner {
        uint256 _curBalance = address(this).balance;
        IWETH(addDef["nativeToken"]).deposit{value: _amount > _curBalance ? _curBalance : _amount}();
    }

    // ------ Funcs. processing ELP
    function depositElp(address _token, address _elp_n, uint256 _sellAmount) external onlyHandler {
        require(isSupportedToken(_token), "not supported src token");
        require(elpToElpManager[_elp_n] != address(0), "ELP manager not set");
        if (_sellAmount == 0)
            _sellAmount = IERC20(addDef["EUSD"]).balanceOf(address(this));
        _sellEUSD(_token,_sellAmount);
        _buyELP(_token, _elp_n, IERC20(_token).balanceOf(address(this)));
        IElp(_elp_n).burn(address(this), IERC20(_elp_n).balanceOf(address(this)) );
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

    function _sellEUSD(address _tokenOut, uint256 _amount) internal returns (uint256) {
        require(addDef["EUSD"] != address(0), "EUSD not defined");
        require(addDef["RewardRouter"] != address(0), "RewardRouter not set");
        require(IERC20(addDef["EUSD"]).balanceOf(address(this)) >= _amount, "insufficient EUSD");
        IERC20(addDef["EUSD"]).approve(addDef["RewardRouter"], _amount);
        uint256 out_amount = 0;
        if (_tokenOut == address(0))
            out_amount = IRewardRouter(addDef["RewardRouter"]).sellEUSDNative(_amount);
        else
            out_amount = IRewardRouter(addDef["RewardRouter"]).sellEUSD(_tokenOut, _amount);

        emit SellESUD(_tokenOut, _amount, out_amount);
        return out_amount;
    }

    function balanceOf(address _token) public view returns (uint256){
        return _token == address(0) ? address(this).balance : IERC20(_token).balanceOf(address(this));
    }
    // Func. public view
    function isSupportedToken(address _token) public view returns(bool){
        return supportedToken.contains(_token);
    }
}
