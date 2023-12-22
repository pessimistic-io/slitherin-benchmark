// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
// import {ERC721} from "@rari-capital/solmate/src/tokens/ERC721.sol";

import {Owned} from "./Owned.sol";
import {ReentrancyGuard} from "./ReentrancyGuard.sol";
import "./Strings.sol";
import "./introspection_IERC165.sol";
// import "./DiscreteGDA.sol";
import {ERC721} from "./ERC721.sol";
import {PRBMathSD59x18} from "./PRBMathSD59x18.sol";

contract KowLoonFoo is ERC721, Owned, ReentrancyGuard {
    using PRBMathSD59x18 for int256;

    // 2000 NFTs
    uint256 public immutable collectionSize;

    uint256 public numSold = 0;
    int256 public limit = 133_084258667509499441;

    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _collectionSize // 2877
    ) ERC721(_name, _symbol) Owned(msg.sender) {
        collectionSize = _collectionSize;
    }

    ///@notice parameter that controls initial price, stored as a 59x18 fixed precision number

    // int256 internal initialPrice;
    int256 public initialPrice;

    ///@notice parameter that controls how much the starting price of each successive auction increases by.
    // initially one variable called scaleFactor, it is now broken into two to offer more fine-grained control over the numbers.
    // But also because using int256 is simply not stored as a 59x18 fixed precision number when it's a public variable.
    int256 public scaleFactorNum;
    int256 public scaleFactorDen;

    ///@notice initially conceived as the decayConstant - replaced now by halfLife
    // Note that the half life here refers to the half life if price decayed without any sales
    int256 public halfLife;

    ///@notice start time for all auctions, stored as a 59x18 fixed precision number

    int256 public auctionStartTime;

    error InsufficientPayment();

    error UnableToRefund();

    error AuctioningOffTooMany();

    error PurchasingTooMany();

    error AuctionAlreadyInProgress();

    error GiftingTooMany();

    error NonExistentTokenURI();

    error NoEthBalance();

    error NotWithdrawn();

    error AuctionNotYetStarted();

    event AuctionStarted(
        int256 _initialPrice,
        int256 _scaleFactorNum,
        int256 _scaleFactorDen,
        int256 _halfLife,
        int256 _auctionStartTime,
        uint256 _amount
    );

    event Log(string func, address sender, uint256 value, bytes data);

    // Setting up GDA for a bunch of tokens

    ///@notice id of current ERC721 being minted
    uint256 public currentId = 0;

    ///@notice number of tokens to be auctioned off in the on-going auction
    uint256 public auctionable = 0;
    ///@notice number of gifted tokens
    uint256 public gifted = 0;
    ///@notice total number of tokens already auctioned or auctionable
    uint256 public auctioned = 0;

    ///@notice basicTokenURI
    string public baseTokenURI;

    function setNewGDA(
        int256 _initialPrice, // inputs are now measured in wei. 10 ** 18 = 1 ether
        int256 _scaleFactorNum,
        int256 _scaleFactorDen,
        int256 _halfLife,
        int256 _auctionStartTime,
        uint256 _amount
    ) public onlyOwner nonReentrant {
        if (auctionable != 0) {
            revert AuctionAlreadyInProgress();
        }
        if (_amount + gifted > collectionSize) {
            revert AuctioningOffTooMany();
        } else {
            numSold = 0;
            initialPrice = _initialPrice; // We are not using fromInt() here because it would make it impossible for us to initialise the price with decimals or literals
            scaleFactorNum = _scaleFactorNum.fromInt();
            scaleFactorDen = _scaleFactorDen.fromInt();
            halfLife = _halfLife.fromInt();
            auctionStartTime = _auctionStartTime.fromInt();
            auctionable = _amount;
            auctioned += _amount;
            emit AuctionStarted(
                initialPrice,
                scaleFactorNum,
                scaleFactorDen,
                halfLife,
                auctionStartTime,
                auctionable
            );
        }
    }

    // Function to receive Ether. msg.data must be empty
    receive() external payable {
        emit Log("receive", msg.sender, msg.value, "");
    }

    // Fallback function is called when msg.data is not empty
    fallback() external payable {
        require(msg.data.length == 0, "msg.data is not empty");
        emit Log("fallback", msg.sender, msg.value, msg.data);
    }

    function gift(uint256 numTokens, address to)
        public
        payable
        onlyOwner
        nonReentrant
    {
        if (collectionSize - (gifted + auctioned + numTokens) < 0) {
            revert GiftingTooMany();
        }

        for (uint256 i = 0; i < numTokens; i++) {
            _mint(to, ++currentId);
        }
        gifted += numTokens;
    }

    ///@notice purchase a specific number of tokens from the GDA
    function purchaseTokens(uint256 numTokens, address to)
        public
        payable
        nonReentrant
    {
        if (int256(block.timestamp).fromInt() < auctionStartTime) {
            revert AuctionNotYetStarted();
        }
        uint256 cost = purchasePrice(numTokens);
        if (auctionable < numTokens) {
            revert PurchasingTooMany();
        }
        if (msg.value < cost) {
            revert InsufficientPayment();
        }

        //mint all tokens
        for (uint256 i = 0; i < numTokens; i++) {
            _mint(to, ++currentId);
        }
        //refund extra payment
        uint256 refund = (cost == 0 ? 0 : msg.value - cost);
        // uint256 refund = msg.value - cost;

        (bool sent, ) = msg.sender.call{value: refund}("");

        if (!sent) {
            revert UnableToRefund();
        } else {
            auctionable -= numTokens;
            numSold += 1;
        }
    }

    ///@notice calculate purchase price using exponential discrete GDA formula
    function purchasePrice(uint256 numTokens) public view returns (uint256) {
        int256 quantity = int256(numTokens).fromInt();
        int256 sold = int256(numSold).fromInt();

        int256 timeSinceStart = int256(block.timestamp).fromInt() -
            auctionStartTime;

        int256 scaleFactor = scaleFactorNum.div(scaleFactorDen); // How much are you going to scale up the price if someone bought an amount. Should be > 1 but not be too big.
        int256 decayConstant = PRBMathSD59x18.ln(PRBMathSD59x18.fromInt(2)).div(
            halfLife
        );

        int256 criticalTime = limit.div(decayConstant);

        int256 num1 = initialPrice.mul(scaleFactor.pow(sold));
        int256 num2 = scaleFactor.pow(quantity) - PRBMathSD59x18.fromInt(1);

        int256 decay = (
            decayConstant.mul(timeSinceStart) >= limit
                ? (limit.floor().exp() + int256(block.timestamp) - criticalTime) // PRBMathSD59x18.fromInt(1).div( // (PRBMathSD59x18.fromInt(133).exp() + // int256(block.timestamp).fromInt() - // criticalTime)
                : ((decayConstant.mul(timeSinceStart)).exp())
        );

        int256 den = scaleFactor - PRBMathSD59x18.fromInt(1);
        int256 totalCost = ((num1.mul(num2)).div(den.mul(decay)));

        return (uint256(totalCost));
    }

    //////////////////////////////////////////////////////////////////////////////////////////
    // * Token URI  *
    //////////////////////////////////////////////////////////////////////////////////////////
    function setBaseURI(string memory baseTokenURI_) public onlyOwner {
        baseTokenURI = baseTokenURI_;
    }

    function tokenURI(uint256 tokenId)
        public
        view
        virtual
        override
        returns (string memory)
    {
        string memory baseURI = baseTokenURI;
        if (ownerOf[tokenId] == address(0)) {
            revert NonExistentTokenURI();
        }
        return (
            bytes(baseURI).length > 0
                ? string(
                    abi.encodePacked(
                        baseURI,
                        "/",
                        Strings.toString(tokenId),
                        ".json"
                    )
                )
                : ""
        );
    }

    //////////////////////////////////////////////////////////////////////////////////////////
    // * Royalties and Balances  *//
    //////////////////////////////////////////////////////////////////////////////////////////
    /// @notice Withdraw all ETH from the contract to the vault addres.
    function withdraw() public onlyOwner {
        if (address(this).balance == 0) {
            revert NoEthBalance();
        }
        (bool sent, ) = address(owner).call{value: address(this).balance}("");
        if (!sent) {
            revert NotWithdrawn();
        }
    }

    function viewBalance() public view returns (uint256 balance) {
        return (address(this).balance);
    }

    // Royalties
    uint256 public royaltyPercent;

    function setRoyaltyPercent(uint256 newRoyaltyPercent) public onlyOwner {
        royaltyPercent = newRoyaltyPercent;
    }

    function royaltyInfo(uint256 salePrice)
        public
        view
        returns (address receiver, uint256 royaltyAmount)
    {
        receiver = owner;
        royaltyAmount = uint256(int256(royaltyPercent * salePrice).div(100));
    }
}

