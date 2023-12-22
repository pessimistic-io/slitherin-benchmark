/*                               %@@@@@@@@@@@@@@@@@(                              
                        ,@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@                        
                    /@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@.                   
                 &@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@(                
              ,@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@              
            *@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@            
           @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@          
         &@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@*        
        @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@&       
       @@@@@@@@@@@@@   #@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@   &@@@@@@@@@@@      
      &@@@@@@@@@@@    @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@.   @@@@@@@@@@,     
      @@@@@@@@@@&   .@@@@@@@@@@@@@@@@@&@@@@@@@@@&&@@@@@@@@@@@#   /@@@@@@@@@     
     &@@@@@@@@@@    @@@@@&                 %          @@@@@@@@,   #@@@@@@@@,    
     @@@@@@@@@@    @@@@@@@@%       &&        *@,       @@@@@@@@    @@@@@@@@%    
     @@@@@@@@@@    @@@@@@@@%      @@@@      /@@@.      @@@@@@@@    @@@@@@@@&    
     @@@@@@@@@@    &@@@@@@@%      @@@@      /@@@.      @@@@@@@@    @@@@@@@@/    
     .@@@@@@@@@@    @@@@@@@%      @@@@      /@@@.      @@@@@@@    &@@@@@@@@     
      @@@@@@@@@@@    @@@@&         @@        .@          @@@@.   @@@@@@@@@&     
       @@@@@@@@@@@.   @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@    @@@@@@@@@@      
        @@@@@@@@@@@@.  @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@   @@@@@@@@@@@       
         @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@        
          @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@#         
            @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@           
              @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@             
                &@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@/               
                   &@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@(                  
                       @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@#                      
                            /@@@@@@@@@@@@@@@@@@@@@@@*  */
// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "./ImAirdrop.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./SafeMath.sol";
import "./SafeERC20.sol";


/*
Controla la emisión de los mAirdrop (ERC20) y su precio
*/
contract mAirdropManager is Ownable, ReentrancyGuard{

    //Libraries
    using SafeERC20 for IERC20;
    using SafeERC20 for ImAirdrop;
    using SafeMath for uint256;


    //Attributes
    uint256 public dateIni;
    uint256 public dateEnd;
    bool public active;
    uint256 public mAirdropDecimals;
    ImAirdrop public mAirdrop;
    mapping(address => uint256) public mAirdropTokenPrice;
    mapping(address => mapping(address => uint256)) public depositedUserToken;

    //Events
    event Deposited(address sender, address token, uint256 amount);
    event MovedToFarm(address destination, address token, uint256 amount);


    //Setters
    function setDateIni(uint256 date) external onlyOwner{
        dateIni = date;
    }
    function setDateEnd(uint256 date) external onlyOwner{
        dateEnd = date;
    }
    function setActive(bool activeSet) external onlyOwner{
        active = activeSet;
    }
    function setmAirdrop(ImAirdrop newmAirdrop) external onlyOwner{
        mAirdrop = newmAirdrop;
        mAirdropDecimals = IERC20Metadata(address(newmAirdrop)).decimals();
    }
    function setTokenPrice(address tokenIn, uint256 price) external onlyOwner{
        mAirdropTokenPrice[tokenIn] = price;
    }


    //Methods
    function deposit(address tokenIn, uint256 amountIn) external nonReentrant{
        require(mAirdropTokenPrice[tokenIn] > 0, "mAirdropManager: price not set");
        require(active, "mAirdropManager: not active");
        require(block.timestamp >= dateIni, "mAirdropManager: not started");
        require(block.timestamp <= dateEnd, "mAirdropManager: ended");

        IERC20 erc20in = IERC20(tokenIn);

        uint256 amountOut = amountIn.mul(10**mAirdropDecimals).div(mAirdropTokenPrice[tokenIn]);
        erc20in.safeTransferFrom(msg.sender, address(this), amountIn);
        mAirdrop.mint(msg.sender, amountOut);
        depositedUserToken[msg.sender][tokenIn] += amountIn;

        emit Deposited(msg.sender, tokenIn, amountIn);
    }

    function transferToFarm(address token, address destination, uint256 amount) external onlyOwner{
        mAirdrop.safeTransfer(destination, amount);

        emit MovedToFarm(destination, token, amount);
    }
}
