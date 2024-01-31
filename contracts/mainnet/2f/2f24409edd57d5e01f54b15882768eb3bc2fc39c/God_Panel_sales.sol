pragma solidity ^0.8.7;
// SPDX-Licence-Identifier: RIGHT-CLICK-SAVE-ONLY

import "./ERC721Enumerable.sol";
import "./Strings.sol";
import "./SafeMath.sol";
import "./Ownable.sol";
import "./IERC1820Registry.sol";
import "./ReentrancyGuard.sol";
import "./IERC777Recipient.sol";
import "./IERC777.sol";

import "./community_interface.sol";

import "./sale_configuration.sol";

import "./recovery.sol";
import "./IRNG.sol";

import "./dusty.sol";
import "./card_with_card.sol";

import "./token_interface.sol";

// import "hardhat/console.sol";

struct sale_data {
    uint256 maxTokens;
    uint256 mintPosition;
    address[] wallets;
    uint16[] shares;
    uint256 fullPrice;
    uint256 discountPrice;
    uint256 presaleStart; // obsolete
    uint256 presaleEnd; // obsolete
    uint256 saleStart;
    uint256 saleEnd;
    uint256 dustPrice; // obsolete
    bool areTokensLocked;
    uint256 maxFreeEC; // obsolete
    uint256 totalFreeEC; // obsolete
    uint256 maxDiscount; // obsolete
    uint256 totalDiscount; // obsolete
    uint256 freePerAddress; // obsolete
    uint256 discountedPerAddress; // obsolete
    string tokenPreRevealURI;
    address signer;
    bool presaleIsActive;
    bool saleIsActive;
    bool dustMintingActive;
    uint256 freeClaimedByThisUser;
    uint256 discountedClaimedByThisUser;
    address etherCards;
    address DUST;
    address ecVault;
    uint256 maxPerSaleMint;
    uint256 MaxUserMintable;
    uint256 userMinted;
    bool randomReceived;
    bool secondReceived;
    uint256 randomCL;
    uint256 randomCL2;
    uint256 ts1;
    uint256 ts;
}

struct sale_params {
    uint256 projectID;
    token_interface token;
    IERC721 ec;
    address dust;
    uint256 maxTokens;
    uint256 maxDiscount; //<--- max sold in presale across presale dust / eth
    uint256 maxPerSaleMint;
    uint256 clientMintLimit;
    uint256 ecMintLimit;
    uint256 discountedPerAddress; //<-- should apply to all presale
    uint256 freeForEC; //<-- for EC card holders
    uint256 discountPrice; //<-- for EC card holders - if zero not available should have *** dust ***
    uint256 discountDustPrice; //<-- for EC card holders - if zero not available should have *** dust ***
    uint256 fullPrice;
    address signer;
    uint256 saleStart;
    uint256 saleEnd;
    uint256 presaleStart;
    uint256 presaleEnd;
    uint256 fullDustPrice;
    address[] wallets;
    uint16[] shares;
}

// check approval limit - start / end of presale

contract God_Panel_sales is
    sale_configuration,
    Ownable,
    recovery,
    ReentrancyGuard,
    dusty,
    card_with_card
{
    using SafeMath for uint256;
    using Strings for uint256;

    // bytes32 constant private TOKENS_RECIPIENT_INTERFACE_HASH = keccak256("ERC777TokensRecipient");
    //IERC1820Registry internal constant _ERC1820_REGISTRY = IERC1820Registry(0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24);

    uint256 public immutable projectID;
    token_interface public _token;

    // bool                        _dustMintActive;

    uint256 immutable _MaxUserMintable;
    uint256 _userMinted;

    uint256 _ts1;
    uint256 _ts2;

    address public _communityAddress;

    mapping(uint256 => bool) public _claimed;

    address public immutable _DUST;
    IERC721 public immutable _EC;
    IERC721 public loveHeals;

    mapping(address => uint256) _freeClaimedPerWallet;
    mapping(address => uint256) _discountedClaimedPerWallet;
    mapping(address => uint256) _publicSoldPerWallet;

    //   mapping (address => uint256)        _dusted;

    event RandomProcessed(
        uint256 stage,
        uint256 randUsed_,
        uint256 _start,
        uint256 _stop,
        uint256 _supply
    );
    event ETHPresale(address from, uint256 number_of_items, uint256 price);
    event ETHSale(address buyer, uint256 number_to_buy, uint256 ethAmount);
    event Allowed(address, bool);

    modifier onlyAllowed() {
        require(
            _token.permitted(msg.sender) || (msg.sender == owner()),
            "Unauthorised"
        );
        _;
    }

    // the constructor takes the bare minimum to conduct a presale and sale.

    constructor(sale_params memory sp)
        dusty(
            sp.dust,
            sp.signer,
            sp.fullDustPrice,
            sp.discountDustPrice,
            sp.maxPerSaleMint,
            sp.wallets,
            sp.shares
        )
        card_with_card(sp.signer)
    {
        projectID = sp.projectID;
        _EC = sp.ec;
        _token = sp.token;
        _DUST = sp.dust;
        _MaxUserMintable = sp.maxTokens - (sp.clientMintLimit + sp.ecMintLimit);

        _maxSupply = sp.maxTokens;
        _maxDiscount = sp.maxDiscount;

        _discountedPerAddress = sp.discountedPerAddress;
        _discountPrice = sp.discountPrice;
        _fullPrice = sp.fullPrice;

        _saleStart = sp.saleStart;
        _saleEnd = sp.saleEnd;

        _presaleStart = sp.presaleStart;
        _presaleEnd = sp.presaleEnd;

        _maxFreeEC = sp.freeForEC;
    }

    function _split(uint256 amount) internal {
        //  console.log("num wallets",wallets.length);
        bool sent;
        uint256 _total;
        for (uint256 j = 0; j < wallets.length; j++) {
            uint256 _amount = (amount * shares[j]) / 1000;
            if (j == wallets.length - 1) {
                _amount = amount - _total;
            } else {
                _total += _amount;
            }
            (sent, ) = wallets[j].call{value: _amount}(""); // don't use send or xfer (gas)
            require(sent, "Failed to send Ether");
        }
    }

    function bumpDiscount(address msgSender, uint256 numberOfCards)
        internal
        override
    {
        _discountedClaimedPerWallet[msgSender] += numberOfCards;
        require(
            _discountedClaimedPerWallet[msgSender] + presold[msgSender] <=
                _discountedPerAddress,
            "you have reached your presale limit"
        );
    }

    function checkBuyerHasEthercards(address _buyer) internal view override {
        require(_EC.balanceOf(_buyer) > 0, "You do not hold Ether Cards");
    }

    function setup(IERC721 _loveHeals) external onlyOwner {
        loveHeals = _loveHeals;
    }

    function checkDiscountAvailable(address _buyer)
        public
        view
        returns (
            bool[3] memory,
            bool,
            uint256,
            uint256,
            uint256
        )
    {
        bool _ec = _EC.balanceOf(_buyer) > 0;
        bool _loveHeals = loveHeals.balanceOf(_buyer) > 0;

        bool _final = (_ec || _loveHeals);

        return (
            [_ec, _loveHeals, true],
            _final,
            _discountedClaimedPerWallet[_buyer], // EC
            presold[_buyer], // whitelist
            _publicSoldPerWallet[_buyer] // Public
        );
    }

    function mintDiscountPresaleWithGalaxis(uint256 numberOfCards)
        external
        payable
    {
        require(_discountPrice != 0, "No EC presale available");
        require(checkPresaleIsActive(), "presale not open");
        (, bool _can, , , ) = checkDiscountAvailable(msg.sender);
        require(_can, "!Available");
        bumpDiscount(msg.sender, numberOfCards);
        _mintPayable(numberOfCards, msg.sender, _discountPrice);
    }

    /*
    function mint_approved_old(bytes calldata userData) external payable {
        // console.log("inside mint_approved_old");
        vData memory info;
        uint256 amount = msg.value;
        address from = msg.sender;
        uint256 number_of_items;
        require(userData.length == 257, "Invalid user data");
        info.from = from;
        info.start = uint256(bytes32(userData[0:32])); // 32
        info.end = uint256(bytes32(userData[32:64])); // 64
        info.eth_price = uint256(bytes32(userData[64:96])); // 96
        info.dust_price = uint256(bytes32(userData[96:128])); // 128
        info.max_mint = uint256(bytes32(userData[128:160])); // 128
        uint256 mint_free = uint256(bytes32(userData[160:192]));
        info.mint_free = mint_free != 0;
        info.signature = bytes(userData[192:257]); // 160

        //    console.log("mint free",info.mint_free);

        require(verify(info), "Unauthorised access secret");
        require(block.timestamp > info.start, "sale period not started");
        require(block.timestamp < info.end, "sale period over");
        require(
            info.eth_price > 0 || info.mint_free,
            "presale minting not available"
        );
        number_of_items = amount / info.eth_price;
        require(
            number_of_items * info.eth_price == amount,
            "incorrect ETH sent"
        );
        uint256 _presold = presold[from];
        require(
            (_presold < info.max_mint),
            "You have already minted your allowance"
        );
        require(
            _presold + number_of_items <= info.max_mint,
            "you have reached your presale limit"
        );
        //     console.log("prices",amount, info.eth_price, number_of_items);
        //     console.log("mint ",number_of_items);
        //     console.log("max_purchase",info.max_mint);
        _mintCards(number_of_items, from);
        //    console.log("before split",address(this).balance,amount);
        _split(amount);
        //  console.log("after split",address(this).balance,amount);
        emit ETHPresale(from, number_of_items, info.eth_price);
    }
*/
    function mint_approved(vData memory info, uint256 number_of_items_requested)
        external
        payable
    {
        uint256 amount = msg.value;
        address from = msg.sender;
        uint256 number_of_items;
        info.from = from;
        require(verify(info), "Unauthorised access secret");
        require(block.timestamp > info.start, "sale period not started");
        require(block.timestamp < info.end, "sale period over");
        require(
            info.eth_price > 0 || info.mint_free,
            "presale minting not available"
        );
        if (info.mint_free) {
            number_of_items = number_of_items_requested;
        } else {
            number_of_items = amount / info.eth_price;
            require(
                number_of_items == number_of_items_requested,
                "ETH sent does not match items requested"
            );
        }
        require(
            number_of_items * info.eth_price == amount,
            "incorrect ETH sent"
        );
        uint256 _presold = presold[from];
        require(
            (_presold < info.max_mint),
            "You have already minted your allowance"
        );
        require(
            _presold + number_of_items <= info.max_mint,
            "you have reached your presale limit"
        );
        presold[from] = _presold + number_of_items;
        require(
            _discountedClaimedPerWallet[from] + presold[from] <=
                _discountedPerAddress,
            "Presale limit"
        );
        _mintCards(number_of_items, from);
        _split(amount);
        emit ETHPresale(from, number_of_items, info.eth_price);
    }

    // make sure this respects ec_limit and client_limit
    function mint(uint256 numberOfCards) external payable {
        require(checkSaleIsActive(), "sale is not open");

        _publicSoldPerWallet[msg.sender] += numberOfCards;
        require(
            _publicSoldPerWallet[msg.sender] <= maxPerSaleMint,
            "pub exceed"
        );
        require(
            numberOfCards <= maxPerSaleMint,
            "Exceeds max per Transaction Mint"
        );
        _mintPayable(numberOfCards, msg.sender, _fullPrice);
    }

    function _mintPayable(
        uint256 numberOfCards,
        address recipient,
        uint256 price
    ) internal override {
        require(msg.value == numberOfCards.mul(price), "wrong amount sent");
        _mintCards(numberOfCards, recipient);
        _split(msg.value);
    }

    function _mintCards(uint256 numberOfCards, address recipient)
        internal
        override(dusty, card_with_card)
    {
        _userMinted += numberOfCards;
        require(
            _userMinted <= _MaxUserMintable,
            "This exceeds maximum number of user mintable cards"
        );
        _token.mintCards(numberOfCards, recipient);
    }

    function _mintDiscountCards(uint256 numberOfCards, address recipient)
        internal
        override(dusty, card_with_card)
    {
        _totalDiscount += numberOfCards;
        require(
            _maxDiscount >= _totalDiscount,
            "Too many discount tokens claimed"
        );
        _mintCards(numberOfCards, recipient);
    }

    function _mintDiscountPayable(
        uint256 numberOfCards,
        address recipient,
        uint256 price
    ) internal override(card_with_card) {
        require(msg.value == numberOfCards.mul(price), "wrong amount sent");
        _mintDiscountCards(numberOfCards, recipient);
        _split(msg.value);
    }

    function setSaleDates(uint256 start, uint256 end) external onlyAllowed {
        _saleStart = start;
        _saleEnd = end;
    }

    function setPresaleDates(uint256 _start, uint256 _end)
        external
        onlyAllowed
    {
        _presaleStart = _start;
        _presaleEnd = _end;
    }

    function checkSaleIsActive() public view override returns (bool) {
        if ((_saleStart <= block.timestamp) && (_saleEnd >= block.timestamp))
            return true;
        return false;
    }

    function checkPresaleIsActive() public view override returns (bool) {
        if (
            (_presaleStart <= block.timestamp) &&
            (_presaleEnd >= block.timestamp)
        ) return true;
        return false;
    }

    function eligibleTokens(uint256[] memory tokenIds)
        internal
        returns (uint256)
    {
        uint256 count;
        for (uint256 j = 0; j < tokenIds.length; j++) {
            uint256 tokenId = tokenIds[j];
            require(
                _EC.ownerOf(tokenId) == msg.sender,
                "You do not own all tokens"
            );
            if (!_claimed[tokenId]) {
                _claimed[tokenId] = true;
                count++;
            }
        }
        return count;
    }

    uint256[] shares2 = [100, 300, 300, 300];

    address payable[] wallets2 = [
        payable(0x183F09b44dFD00883D687F677066347F6E9AC875),
        payable(0xBe0a92732Ee7983660B635013A6280549fc6e250),
        payable(0xc572567ab7433de6F08F2287Ee84C0D5Ad870490),
        payable(0x82B7e56A5b2ac87E53e369338026A1Bc03284611)
    ];

    function setWallets(
        address payable[] memory _wallets,
        uint256[] memory _shares
    ) public onlyOwner {
        require(_wallets.length == _shares.length, "!lenght");
        wallets2 = _wallets;
        shares2 = _shares;
    }

    function _split2(uint256 amount) internal {
        // duplicated to save an extra call
        bool sent;
        uint256 _total;
        for (uint256 j = 0; j < wallets2.length; j++) {
            uint256 _amount = (amount * shares2[j]) / 1000;
            if (j == wallets2.length - 1) {
                _amount = amount - _total;
            } else {
                _total += _amount;
            }
            (sent, ) = wallets2[j].call{value: _amount}(""); // don't use send or xfer (gas)
            require(sent, "Failed to send Ether");
        }
    }

    receive() external payable {
        _split2(msg.value);
    }

    function tellEverything(address addr)
        external
        view
        returns (sale_data memory)
    {
        // if community module active - get the community.taken[msg.sender]

        token_interface.TKS memory tokenData = _token.tellEverything();

        uint256 community_claimed;
        if (_communityAddress != address(0)) {
            community_claimed = community_interface(_communityAddress)
                .community_claimed(addr);
        }

        return
            sale_data(
                _maxSupply,
                tokenData._mintPosition,
                wallets,
                shares,
                _fullPrice,
                _discountPrice,
                _presaleStart,
                _presaleEnd,
                _saleStart,
                _saleEnd,
                _dustPrice,
                tokenData._lockTillSaleEnd,
                _maxFreeEC,
                _totalFreeEC,
                _maxDiscount,
                _totalDiscount,
                _freePerAddress,
                _discountedPerAddress,
                _token.tokenPreRevealURI(),
                _signer,
                checkPresaleIsActive(),
                checkSaleIsActive(),
                checkSaleIsActive() &&
                    (fullDustPrice > 0 || discountDustPrice > 0),
                _freeClaimedPerWallet[addr],
                _discountedClaimedPerWallet[addr],
                address(_EC),
                _DUST,
                _ecVault,
                maxPerSaleMint,
                _MaxUserMintable,
                _userMinted,
                tokenData._randomReceived,
                tokenData._secondReceived,
                tokenData._randomCL,
                tokenData._randomCL2,
                tokenData._ts1,
                tokenData._ts2
            );
    }
}

