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
import "./IMuchoBadgeManager.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./SafeMath.sol";
import "./SafeERC20.sol";
import "./EnumerableSet.sol";

/*
Controla la emisión de los mAirdrop (ERC20) y su precio
*/
contract mAirdropManager is Ownable, ReentrancyGuard {
    //Libraries
    using SafeERC20 for IERC20;
    using SafeERC20 for ImAirdrop;
    using SafeMath for uint256;
    using EnumerableSet for EnumerableSet.UintSet;

    //Contracts interaction
    IMuchoBadgeManager public mBadge =
        IMuchoBadgeManager(0xC439d29ee3C7fa237da928AD3A3D6aEcA9aA0717);

    //Attributes
    uint256 public dateIni;
    uint256 public dateEnd;
    uint256 public dateRampIni;
    uint256 public dateRampEnd;
    bool public active;
    uint256 public mAirdropDecimals;
    ImAirdrop public mAirdrop;
    mapping(address => uint256) public mAirdropTokenPriceRampIni;
    mapping(address => uint256) public mAirdropTokenPriceRampEnd;
    mapping(address => mapping(address => uint256)) public depositedUserToken;
    bool public onlyNFTHolders;
    EnumerableSet.UintSet private nftAllowed;

    //Events
    event Deposited(address sender, address token, uint256 amount);
    event Transferred(address destination, address token, uint256 amount);
    event Airdrop(address destination, uint256 amount);

    //Views
    function getNftAllowedList() external view returns (uint256[] memory list) {
        list = new uint256[](nftAllowed.length());
        for (uint256 i = 0; i < list.length; i++) {
            list[i] = nftAllowed.at(i);
        }
    }

    function mAirdropTokenPrice(
        address token
    ) external view returns (uint256 price) {
        price = _getCurrentPrice(token);
    }

    //Setters
    function setBadgeManager(IMuchoBadgeManager newBadge) external onlyOwner {
        mBadge = newBadge;
    }

    function setDateIni(uint256 date) external onlyOwner {
        dateIni = date;
    }

    function setDateEnd(uint256 date) external onlyOwner {
        dateEnd = date;
    }

    function setDateRampIni(uint256 date) external onlyOwner {
        dateRampIni = date;
    }

    function setDateRampEnd(uint256 date) external onlyOwner {
        dateRampEnd = date;
    }

    function setActive(bool activeSet) external onlyOwner {
        active = activeSet;
    }

    function setmAirdrop(ImAirdrop newmAirdrop) external onlyOwner {
        mAirdrop = newmAirdrop;
        mAirdropDecimals = IERC20Metadata(address(newmAirdrop)).decimals();
    }

    function setTokenPriceRampIni(
        address tokenIn,
        uint256 price
    ) external onlyOwner {
        mAirdropTokenPriceRampIni[tokenIn] = price;
    }

    function setTokenPriceRampEnd(
        address tokenIn,
        uint256 price
    ) external onlyOwner {
        mAirdropTokenPriceRampEnd[tokenIn] = price;
    }

    function addNftAllowed(uint256 nftId) external onlyOwner {
        nftAllowed.add(nftId);
    }

    function removeNftAllowed(uint256 nftId) external onlyOwner {
        nftAllowed.remove(nftId);
    }

    function setOnlyNft(bool onlyNft) external onlyOwner {
        onlyNFTHolders = onlyNft;
    }

    //Methods
    function deposit(address tokenIn, uint256 amountIn) external nonReentrant {
        require(active, "mAirdropManager: not active");
        require(block.timestamp >= dateIni, "mAirdropManager: not started");
        require(block.timestamp <= dateEnd, "mAirdropManager: ended");
        require(
            !onlyNFTHolders || hasValidNft(msg.sender),
            "mAirdropManager: no valid NFT"
        );
        require(
            _getCurrentPrice(tokenIn) > 0,
            "mAirdropManager: price not set"
        );

        IERC20 erc20in = IERC20(tokenIn);

        uint256 amountOut = amountIn.mul(10 ** mAirdropDecimals).div(
            _getCurrentPrice(tokenIn)
        );
        erc20in.safeTransferFrom(msg.sender, address(this), amountIn);
        mAirdrop.mint(msg.sender, amountOut);
        depositedUserToken[msg.sender][tokenIn] += amountIn;

        emit Deposited(msg.sender, tokenIn, amountIn);
    }

    function transferToken(
        address token,
        address destination,
        uint256 amount
    ) external onlyOwner {
        IERC20(token).safeTransfer(destination, amount);

        emit Transferred(destination, token, amount);
    }

    function hasValidNft(address user) internal view returns (bool) {
        IMuchoBadgeManager.Plan[] memory nfts = mBadge.activePlansForUser(user);
        for (uint256 i = 0; i < nfts.length; i++) {
            if (nftAllowed.contains(nfts[i].id)) {
                return true;
            }
        }

        return false;
    }

    function airdrop(address destination, uint256 amount) public onlyOwner {
        mAirdrop.mint(destination, amount);

        emit Airdrop(destination, amount);
    }

    function bulkAirdrop(
        address[] calldata destination,
        uint256[] calldata amount
    ) external onlyOwner {
        require(
            destination.length == amount.length,
            "mAirdropManager: different length"
        );

        for (uint256 i = 0; i < destination.length; i++) {
            airdrop(destination[i], amount[i]);
        }
    }

    function _getCurrentPrice(
        address token
    ) internal view returns (uint256 price) {
        require(active, "mAirdropManager price: not active");
        require(
            block.timestamp >= dateIni,
            "mAirdropManager price: not started"
        );
        require(block.timestamp <= dateEnd, "mAirdropManager price: ended");

        price = mAirdropTokenPriceRampIni[token];
        if (block.timestamp > dateRampIni && block.timestamp <= dateRampEnd) {
            uint256 priceEnd = mAirdropTokenPriceRampEnd[token];
            uint256 timeElapsed = block.timestamp - dateRampIni;
            uint256 timeRamp = dateRampEnd - dateRampIni;
            if (priceEnd > price) {
                price += priceEnd.sub(price).mul(timeElapsed).div(timeRamp);
            } else if (priceEnd < price) {
                price -= price.sub(priceEnd).mul(timeElapsed).div(timeRamp);
            }
        }
    }
}

