//                                                                          .                         
//                                                                       .JB#BPJ~.                    
//                                                                       ^B@@@@@@&GY!:                
//                           .:~!?JJ?:                                     ~?5B&@@@@@&BY!:            
//                     .~7YPB#&@@@@@@#.                                        :~JP#@@@@@&GJ^         
//                  ^?P&@@@@@@@@@&#B5!                                             .^?5B&@@@@5:       
//               :?B@@@@@&#BPJ7~^:.                                                     :!5#@@&?      
//             ^Y&@@@#57~:.                                                                .?#@@P.    
//           ^5&@@#Y~.                                                                       .Y@@5    
//         ^5@@@#J.                                                            :75GB##BBGG5J!. ~PG.   
//       ^P@@@#J.                                                           :?G#BP5JJYYYYY5PGG~       
//     .Y@@@G7.                                                            !#P7?PB&!J@&&&&#GPJ:       
//    ^B@@G~                ..:^^^^^:.                                     ..^P@@#P:5@@@@@@@@@B~      
//   ^&@G!           :~?YPGBB####&&&&&P                                    .5@@@#.  .G@@@@@@&J@@~     
//   ^5?         :?PB#BGP5JJ7!~^:..:^~^                                   :B@@@@B    !@@@@@@&:#@&~    
//             7G&B55PGB#&&&@@&#BPJ~                                      P@@@@@@7. :P@@@@@@#:&@@&:   
//             ?Y7 JP?775@@@@@@@@@@@#J:                                  :@@&@@@@@#B&@@@@@@@P.@5~&Y   
//           .!YB@J      ?@@@@@@@@@@@@&?                                 J@@!P@@@@@@@@@@@@@@7.B7 ..   
//         :J#@@@@@G?:.  J@@@@@@@@@@@@@@P.                               ~!! 7@@@@@@@@@@@@@&:^!.      
//        J&@@@BG@@@@&#B#@@@@@@@@@@@@@@@@5                               P@#. B@@@@@@@@@@@@J B#       
//       P@@@P!..#@@@@@@@@@@@@@@@@@@@@@@@&:                              J@#. ~@@@@@@@@@@@B !@J       
//      ?@@P^^57 ^&@@@@@@@@@@@@@@@@@@@YP@@J                              !@&:  !&@@@@@@@@&~ 5@:       
//      B@J  B@G  ~&@@@@@@@@@@@@@@@@@@:^@@B                               B@?   ^G@@@@@#Y: ?@?        
//     ^@B   ?@@~  ^#@@@@@@@@@@@@@@@@?  7??.                              ^#@7    ~JYJ~.  Y@J         
//     !#~    G@B.  :G@@@@@@@@@@@@@&7  .PGY                                .Y&G?^.       J&?          
//            :#@P.   7B@@@@@@@@@@G^   7@@5                                  :?G&&BY7~:7J:.           
//             :G@#!    ^?5GBBGY7^    !&@B.                                     .!5B&@@@@PG#~         
//               ?#@G~             .~Y@@B:                                          .^~!!??7:         
//                .7B@BJ~.        .P@@@5.                                                             
//                   :?PB#PJ!^:~JP?^7J^                                                               
//                   ~PPG@@@@@@&#GY^                                                                  
//                   .JBBGP5?7~:.                                                                     
//                                                                                                    
//                                                                                                    
//                                                                 .!.                                
//                                                       ^J7~^^:^!?J!                                 
//                                                        .^~!!!!~:                                   
//                                                                                                    
//                                                                                                    
//                             ✧・ﾟ:𝓁𝒶𝓈𝑒𝓇𝓈 are coming out of my eyes:・ﾟ✧                                     
//                                            $LASEREYES
//                                  https://bitcoinmiladys.com/token
//                                  Smart Contract by @shrimpyuk :^)
//
pragma solidity ^0.8.9;

import "./ERC20.sol";
import "./Ownable.sol";

contract LaserEyes is Ownable, ERC20 {
    bool isDeployed = false;                        //If the contract is deployed
    address public liqudityPoolSwapPair;            //Address of our initial Liquidity Pool


    uint256 public constant SUPPLY_CAP = 10_000_000_000 * 1 ether; //10,000,000,000 supply cap

    //Important Wallets
    address constant teamWallet = 0x532ee831bb3C2Bbe6F60f4Fd523F912699152905;
    address constant marketingWallet = 0x9A0F96122249C72bDE40A68325bDd20Cd962ac4D;
    address constant cexWallet = 0x86E5Ad1cC2e3E4f580C30C61551068B8061B8DD0;
    address constant developerWallet = 0xff955eFf3d270D44B39D228F7ECdfe41aD5760B3;

    // Supply Distribution:
    // 62.5%   Contributors Allocation
    uint constant contributorsAllocation = ((SUPPLY_CAP / 1000)*625); //62.5%
    // 10%     Holders Allocation
    uint constant holdersAllocation = ((SUPPLY_CAP / 1000)*100); //10%
    // 12.5%   Liquidity Pool Allocation
    uint constant liquidityAllocation = ((SUPPLY_CAP / 1000)*125); //12.5%
    // 7.5%    CEX Allocation
    uint constant cexAllocation = ((SUPPLY_CAP / 1000)*75); //7.5%
    // 5%      Marketing Allocation
    uint constant marketingAllocation = ((SUPPLY_CAP / 1000)*50); //5%
    // 2.3%    Team Allocation
    uint constant teamAllocation = ((SUPPLY_CAP / 1000)*23); //2.3%
    // 0.2%    Developer Allocation
    uint constant developerAllocation = ((SUPPLY_CAP / 1000)*2); //0.2%

    constructor() ERC20("Laser Eyes", "LASEREYES") {
        //Mint the Contributor + Holder + Liquidity + Team Allocation to Team Wallet.
        //This is to allow the team to distribute the tokens to the correct places.
        _mint(teamWallet, contributorsAllocation+holdersAllocation+liquidityAllocation+teamAllocation);

        //Mint the Marketing Allocation to the Marketing Wallet.
        _mint(marketingWallet, marketingAllocation);
    
        //Mint the CEX Allocation to the CEX Wallet.
        _mint(cexWallet, cexAllocation);

        //Mint the Developer's Fee to the Developer's Wallet
        _mint(developerWallet, developerAllocation);

        isDeployed = true;

        //Transfer Ownership to the Team. This is to be later renounced.
        _transferOwnership(teamWallet);
    }

    /// @notice Set them tokens on fire
    /// @param value How many tokens to burn
    function burn(uint256 value) external {
        _burn(msg.sender, value);
    }

    /// @notice Set Liquidity Pool to Enable Trading
    /// @param _tokenSwapPair Address of the Token Swap Pair e.g. Uniswap
    function setLiquidityPool(address _tokenSwapPair) external onlyOwner {
        liqudityPoolSwapPair = _tokenSwapPair;
    }

    //Enforce Ruleset
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) override internal virtual {
        // Exclude Pre-Liqudity Trading (Aside from Owner Wallet)
        if (liqudityPoolSwapPair == address(0) && isDeployed) {
            require(from == owner() || to == owner(), "Trading has not yet started");
            return;
        }
    }
}
