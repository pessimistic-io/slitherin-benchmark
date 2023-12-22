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
-Controla la emisión de los mAirdrop (ERC20) y su precio
-Transacciones:
    -Deposit: almacena los USDC que le envia el usuario, y a cambio le emite el token mAirdrop

-Atributos:
    -Fecha inicio, fecha fin: para controlar el lanzamiento
    -Referencia a mAirdrop (ERC20)
    -Precio del mAirdrop
*/
contract mAirdropManager is Ownable, ReentrancyGuard{

    //Libraries
    using SafeERC20 for IERC20;
    using SafeMath for uint256;


    //Attributes
    uint256 public dateIni;
    uint256 public dateEnd;
    bool public active;
    ImAirdrop public mAirdrop;
    mapping(address => uint256) mAirdropTokenPrice;


    //Constructor
    constructor() Ownable(msg.sender) {
    }


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
    }
    function setTokenPrice(address tokenIn, uint256 price) external onlyOwner{
        mAirdropTokenPrice[tokenIn] = price;
    }


    //Methods
    function deposit(address tokenIn, uint256 amountIn) external nonReentrant{
        require(mAirdropTokenPrice[tokenIn] > 0, "mAirdropManager: price not set");

        IERC20 erc20in = IERC20(tokenIn);

        uint256 amountOut = amountIn.div(mAirdropTokenPrice[tokenIn]);
        erc20in.safeTransferFrom(msg.sender, address(this), amountIn);
        mAirdrop.mint(msg.sender, amountOut);
    }
}
