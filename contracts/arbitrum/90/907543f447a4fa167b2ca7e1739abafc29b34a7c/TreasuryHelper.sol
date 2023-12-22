// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./SafeMath.sol";
import "./Address.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";
import "./Ownable.sol";
import "./EnumerableSet.sol";


interface ITreasury {
    function sellEUSD(address _tokenOut, uint256 _amount)  external payable returns (uint256);
    function weight_buy_elp()  external view returns (uint256);
    function weight_EDElp()  external view returns (uint256);
    function buyELP(address _token, address _elp_n, uint256 _amount) external returns (uint256);
    function treasureSwap(address _src, address _dst, uint256 _amount_in, uint256 _amount_out_min) external returns (uint256);

}



contract TreasuryHelper is Ownable{
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    ITreasury public treasury;

    address public eusd;
    address public ede;
    address public elp;
    address public midToken;
    mapping (address => bool) public isHandler;
    
    modifier onlyHandler() {
        require(isHandler[msg.sender] || msg.sender == owner(), "forbidden");
        _;
    }
    function setHandler(address _handler, bool _isActive) external onlyOwner {
        isHandler[_handler] = _isActive;
    }
    function setAddress(address _treasury, address _eusd, address _ede, address _elp) external onlyOwner{
        treasury = ITreasury(_treasury);
        eusd = _eusd;
        ede = _ede;
        elp = _elp;
    }
    function setMidToken(address _midToken) external onlyOwner{
        midToken = _midToken;
    }


    function EusdBuyEdeElp(uint256 _elpWeight) external onlyHandler{
        require(_elpWeight <= 100, "weight too large");
        treasury.sellEUSD(midToken, IERC20(eusd).balanceOf(address(treasury)));
        uint256 _p0_amount = IERC20(midToken).balanceOf(address(treasury));
        if (_p0_amount < 1)
            return;
        uint256 _amountToElp = _p0_amount.mul(_elpWeight).div(100);
        treasury.buyELP(midToken, elp, _amountToElp);

        uint256 _amountToEde = _p0_amount.sub(_amountToElp);
        if (_amountToEde > 0){
            treasury.treasureSwap(midToken, address(0), _amountToEde, 0);
            treasury.treasureSwap(address(0), ede, address(treasury).balance, 0);
        }
    }
}
