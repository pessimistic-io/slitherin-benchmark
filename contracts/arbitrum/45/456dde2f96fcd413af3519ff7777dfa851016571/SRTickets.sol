// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;
import "./ReentrancyGuard.sol";
import "./Counters.sol";
import "./SafeERC20.sol";

import "./AggregatorV3Interface.sol";

contract SRTicketsDiscountsRemote {
    struct DiscountResponse {
        bool hasDiscountCode;
        bool hasDiscountAddress;
        bool hasTokenDiscount;
        uint256 discountAmount;
    }
    address public SRTicketsAddress;

    struct SenderAndTokenDiscountBuyer {
        address sender;
        bool tockenDiscountBuyer;
    }

    function getAttendee(address sender, uint256 index)
        public
        view
        returns (SRTickets.Attendee memory)
    {}

    function getDiscountView(
        SenderAndTokenDiscountBuyer memory stdb,
        bool discountCodeTicketAttendee,
        SRTickets.DiscountCode memory,
        bool discountAddressTicketAttendee,
        SRTickets.DiscountAddress memory,
        bool tokenDiscountTicketAttendee,
        SRTickets.TokenDiscount memory,
        address tokenDiscountAttendee
    ) public view returns (DiscountResponse memory) {}

    function setAttendee(
        uint256 attendeeIndex,
        SRTickets.Attendee memory newAttendee,
        SRTickets.Attendee memory attendee,
        address sender,
        bool resell,
        bool refund
    ) public {}
}

contract SRTickets is ReentrancyGuard {
    using Counters for Counters.Counter;
    address public owner;
    using SafeERC20 for IERC20;
    bool public allowSelfRefund;
    uint256 public refundFee;
    uint256 public resellFee;
    struct Ticket {
        uint256 qty;
        Counters.Counter used;
        uint256 price;
        uint256 endDate;
        uint256 startDate;
    }

    /*  struct DiscountResponse {
        bool hasDiscountCode;
        bool hasDiscountAddress;
        bool hasTokenDiscount;
        uint256 discountAmount;
    }
*/
    struct DiscountCode {
        uint256 qty;
        Counters.Counter used;
        uint256 amount;
        string code;
        uint256 endDate;
        uint256 startDate;
    }

    struct DiscountAddress {
        address buyer;
        uint256 qty;
        Counters.Counter used;
        uint256 amount;
        string code;
        uint256 endDate;
        uint256 startDate;
    }

    struct TokenDiscount {
        address token;
        uint256 minAmount;
        uint256 qty;
        Counters.Counter used;
        uint256 amount;
        uint256 endDate;
        uint256 startDate;
    }

    struct Attendee {
        string email;
        string fname;
        string lname;
        string bio;
        string job;
        string company;
        string social;
        string ticket;
        string discountCode;
        address tokenDiscount;
        address sender;
        address buyToken;
        uint256 pricePaid;
        uint256 pricePaidInToken;
        bool cancelled;
        uint256 refunded;
        bool allowResell;
        uint256 resellPrice;
        string code;
    }

    mapping(string => Ticket) public tickets;
    mapping(string => DiscountCode) public discountCodes;
    mapping(address => DiscountAddress) public discountAddresses;
    mapping(address => TokenDiscount) public tokenDiscounts;
    mapping(address => mapping(string => bool)) public tokenDiscountTickets;
    mapping(address => mapping(address => bool)) public tokenDiscountBuyer;
    mapping(string => mapping(string => bool)) public discountCodeTickets;
    mapping(address => mapping(string => bool)) public discountAddressTickets;

    mapping(address => address) public priceFeeds;

    address public token;
    address private discountContract;
    mapping(address => Counters.Counter) public attendeesCount;

    constructor(address _discountContract) {
        discountContract = _discountContract;
        owner = address(msg.sender);
        allowSelfRefund = true;
        refundFee = 15;
        resellFee = 15;
        //mainnet        priceFeeds[address(0)] = 0x9326BFA02ADD2366b30bacB125260Af641031331;
        //priceFeeds[address(0)] = 0x7f8847242a530E809E17bF2DA5D2f9d2c4A43261; //kovan optimism
        //priceFeeds[address(0)] = 0x13e3Ee699D1909E989722E753853AE30b17e08c5; //mainnet optimism
        priceFeeds[address(0)] = 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612; //mainnet arbitrum
        setTicket(100, 100, 9949326229, 1, "conference-only");
        setTicket(25, 50, 9949326229, 1, "iftar-meetup");
        /* //btc
        priceFeeds[
            0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599
        ] = 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c;
        //usdt
        priceFeeds[
            0xdAC17F958D2ee523a2206206994597C13D831ec7
        ] = 0x3E7d1eAB13ad0104d2750B8863b489D65364e32D;
        //dai
        priceFeeds[
            0x6B175474E89094C44Da98b954EedeAC495271d0F
        ] = 0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9;
        //bnb
        priceFeeds[
            0xB8c77482e45F1F44dE1745F52C74426C631bDD52
        ] = 0x14e613AC84a31f709eadbdF89C6CC390fDc9540A;
        //usdc
        priceFeeds[
            0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
        ] = 0x986b5E1e1755e3C2440e960477f25201B0a8bbD4;
        //link
        priceFeeds[
            0x514910771AF9Ca656af840dff83E8264EcF986CA
        ] = 0x2c1d072e956AFFC0D435Cb7AC38EF18d24d9127c;
        //aave
        priceFeeds[
            0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9
        ] = 0x547a514d5e3769680Ce22B2361c10Ea13619e8a9;
        //tusd
        priceFeeds[
            0x0000000000085d4780B73119b644AE5ecd22b376
        ] = 0xec746eCF986E2927Abd291a2A1716c940100f8Ba;
        //mim
        priceFeeds[
            0x99D8a9C45b2ecA8864373A26D1459e3Dff1e17F3
        ] = 0x7A364e8770418566e3eb2001A96116E6138Eb32F;
        //rai
        priceFeeds[
            0x03ab458634910AaD20eF5f1C8ee96F1D6ac54919
        ] = 0x483d36F6a1d063d580c7a24F9A42B346f3a69fbb;
        //fei
        priceFeeds[
            0x956F47F50A910163D8BF957Cf5846D573E7f87CA
        ] = 0x31e0a88fecB6eC0a411DBe0e9E76391498296EE9;
        //uni
        priceFeeds[
            0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984
        ] = 0x553303d460EE0afB37EdFf9bE42922D8FF63220e;
        //sushi
        priceFeeds[
            0x6B3595068778DD592e39A122f4f5a5cF09C90fE2
        ] = 0xCc70F09A6CC17553b2E31954cD36E4A2d89501f7;
        //xsushi
        priceFeeds[
            0x8798249c2E607446EfB7Ad49eC89dD1865Ff4272
        ] = 0xCC1f5d9e6956447630d703C8e93b2345c2DE3D13;
        //mkr
        priceFeeds[
            0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2
        ] = 0xec1D1B3b0443256cc3860e24a46F108e699484Aa;
        //yfi
        priceFeeds[
            0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e
        ] = 0xA027702dbb89fbd58938e4324ac03B58d812b0E1;
        //comp
        priceFeeds[
            0xc00e94Cb662C3520282E6f5717214004A7f26888
        ] = 0xdbd020CAeF83eFd542f4De03e3cF0C28A4428bd5;
        //matic
        priceFeeds[
            0x7D1AfA7B718fb893dB30A3aBc0Cfc608AaCfeBB0
        ] = 0x7bAC85A8a13A4BcD8abb3eB7d6b4d632c5a57676;
        //1inch
        priceFeeds[
            0x111111111117dC0aa78b770fA6A738034120C302
        ] = 0xc929ad75B72593967DE83E7F7Cda0493458261D9;
        //busd
        priceFeeds[
            0x4Fabb145d64652a948d72533023f6E7A623C7C53
        ] = 0x833D8Eb16D306ed1FbB5D7A2E019e106B960965A;
    */
    }

    modifier validNameSlug(string memory _slug) {
        bytes memory tmpSlug = bytes(_slug); // Uses memory
        require(tmpSlug.length > 0, "Not valid slug");
        _;
    }
    modifier onlyOwner() {
        require(address(msg.sender) == owner, "!owner");
        _;
    }

    function setPriceFeed(address address1, address address2) public onlyOwner {
        priceFeeds[address1] = address2;
    }

    function setToken(address newToken) public onlyOwner {
        token = newToken;
    }

    function setRefund(
        bool allow,
        uint256 rffee,
        uint256 rsfee
    ) public onlyOwner {
        allowSelfRefund = allow;
        refundFee = rffee;
        resellFee = rsfee;
    }

    function setTicket(
        uint256 qty,
        uint256 price,
        uint256 endDate,
        uint256 startDate,
        string memory slug
    ) public validNameSlug(slug) onlyOwner {
        Ticket memory t;
        t.qty = qty;
        t.price = price;
        t.endDate = endDate;
        t.startDate = startDate;
        tickets[slug] = t;
    }

    function setTokenDiscount(
        address discountToken,
        uint256 minAmount,
        uint256 qty,
        uint256 amount,
        uint256 endDate,
        uint256 startDate,
        string[] memory ticketsToAdd,
        string[] memory ticketsToRemove
    ) public onlyOwner {
        TokenDiscount memory td;
        td.token = discountToken;
        td.minAmount = minAmount;
        td.qty = qty;
        td.amount = amount;
        td.endDate = endDate;
        td.startDate = startDate;
        tokenDiscounts[discountToken] = td;

        for (uint256 i = 0; i < ticketsToAdd.length; i++) {
            tokenDiscountTickets[discountToken][ticketsToAdd[i]] = true;
        }
        for (uint256 i = 0; i < ticketsToRemove.length; i++) {
            tokenDiscountTickets[discountToken][ticketsToRemove[i]] = false;
        }
    }

    function setDiscountCodes(
        string memory code,
        uint256 qty,
        uint256 amount,
        uint256 endDate,
        uint256 startDate,
        string[] memory ticketsToAdd,
        string[] memory ticketsToRemove
    ) public onlyOwner {
        DiscountCode memory td;
        td.qty = qty;
        td.amount = amount;
        td.endDate = endDate;
        td.startDate = startDate;
        discountCodes[code] = td;

        for (uint256 i = 0; i < ticketsToAdd.length; i++) {
            discountCodeTickets[code][ticketsToAdd[i]] = true;
        }
        for (uint256 i = 0; i < ticketsToRemove.length; i++) {
            discountCodeTickets[code][ticketsToRemove[i]] = false;
        }
    }

    function setDiscountAddresses(
        address buyer,
        uint256 qty,
        uint256 amount,
        uint256 endDate,
        uint256 startDate,
        string[] memory ticketsToAdd,
        string[] memory ticketsToRemove
    ) public onlyOwner {
        DiscountAddress memory td;
        td.qty = qty;
        td.amount = amount;
        td.endDate = endDate;
        td.startDate = startDate;
        discountAddresses[buyer] = td;

        for (uint256 i = 0; i < ticketsToAdd.length; i++) {
            discountAddressTickets[buyer][ticketsToAdd[i]] = true;
        }

        for (uint256 i = 0; i < ticketsToRemove.length; i++) {
            discountAddressTickets[buyer][ticketsToRemove[i]] = false;
        }
    }

    function mintTicket(Attendee[] memory buyAttendees, address buyToken)
        public
        payable
    {
        uint256 total = 0;
        uint256 discount = 0;
        //AggregatorV3Interface priceFeed;
        uint256 valueToken = 0;
        require(priceFeeds[buyToken] != address(0), "token not supported");
        int256 usdPrice = 326393000000;

        for (uint256 i = 0; i < buyAttendees.length; i++) {
            require(
                tickets[buyAttendees[i].ticket].used.current() <
                    tickets[buyAttendees[i].ticket].qty,
                "sold out"
            );
            require(
                tickets[buyAttendees[i].ticket].startDate < block.timestamp,
                "not available yet"
            );
            require(
                tickets[buyAttendees[i].ticket].endDate > block.timestamp,
                "not available anymore"
            );
            discount = getDiscount(msg.sender, buyAttendees[i]);

            uint256 priceToPay = getPrice(discount, buyAttendees[i].ticket);
            total += priceToPay;
            buyAttendees[i].sender = msg.sender;
            buyAttendees[i].pricePaid = tickets[buyAttendees[i].ticket].price; //priceToPay;
            buyAttendees[i].pricePaidInToken = getPriceFromUSD(priceToPay);

            buyAttendees[i].buyToken = buyToken;
            setAttendee(
                attendeesCount[msg.sender].current(),
                buyAttendees[i],
                buyAttendees[i],
                msg.sender,
                false,
                false
            );
            tickets[buyAttendees[i].ticket].used.increment();
            attendeesCount[msg.sender].increment();
        }
        //AggregatorV3Interface priceFeed;
        //priceFeed = AggregatorV3Interface(priceFeeds[buyToken]);
        //(, int256 price, , , ) = priceFeed.latestRoundData();
        require(total > 0, "total 0");
        if (buyToken == address(0)) {
            require(msg.value >= getPriceFromUSD(total), "price too low");
        } else {
            valueToken = getPriceFromUSD(total);
            require(
                IERC20(buyToken).transferFrom(
                    address(msg.sender),
                    address(this),
                    uint256(valueToken)
                ),
                "transfer failed"
            );
        }
        //emit LMint(msg.sender, mints, "minted");
    }

    function getPriceFromUSD(uint256 priceUSD) private view returns (uint256) {
        AggregatorV3Interface priceFeed;
        priceFeed = AggregatorV3Interface(priceFeeds[address(0)]);
        (, int256 latestPrice, , , ) = priceFeed.latestRoundData();
        //int256 latestPrice = 326393000000;
        uint256 price = uint256(
            (int256(priceUSD * 10**8) * 10**18) / latestPrice
        );
        return price;
    }

    function getPrice(uint256 discount, string memory ticket)
        public
        view
        returns (uint256)
    {
        uint256 price = tickets[ticket].price;
        return price - (price * discount) / 100;
    }

    function getAttendee(address sender, uint256 index)
        private
        view
        returns (Attendee memory attendee)
    {
        SRTicketsDiscountsRemote dc = SRTicketsDiscountsRemote(
            discountContract
        );
        attendee = dc.getAttendee(sender, index);
    }

    function setAttendee(
        uint256 attendeeIndex,
        Attendee memory newAttendee,
        Attendee memory attendee,
        address sender,
        bool resell,
        bool isRefund
    ) private {
        SRTicketsDiscountsRemote dc = SRTicketsDiscountsRemote(
            discountContract
        );
        dc.setAttendee(
            attendeeIndex,
            newAttendee,
            attendee,
            sender,
            resell,
            isRefund
        );
    }

    function getDiscountView(address sender, Attendee memory attendee)
        public
        view
        returns (uint256)
    {
        SRTicketsDiscountsRemote.DiscountResponse memory dr = getDiscountAmount(
            sender,
            attendee
        );
        return dr.discountAmount; //discountCodeTickets["50pc-discount"]["conference-only"];
    }

    function getDiscount(address sender, Attendee memory attendee)
        private
        returns (uint256)
    {
        SRTicketsDiscountsRemote.DiscountResponse memory dr = getDiscountAmount(
            sender,
            attendee
        );
        if (dr.hasDiscountCode) {
            discountCodes[attendee.discountCode].used.increment();
        }
        if (dr.hasDiscountAddress) {
            discountAddresses[sender].used.increment();
        }
        if (dr.hasTokenDiscount) {
            tokenDiscounts[attendee.tokenDiscount].used.increment();
            tokenDiscountBuyer[attendee.tokenDiscount][sender] = true;
        }
        return dr.discountAmount;
    }

    function getDiscountAmount(address sender, Attendee memory attendee)
        private
        view
        returns (SRTicketsDiscountsRemote.DiscountResponse memory)
    {
        //check sender Discount code
        SRTicketsDiscountsRemote dc = SRTicketsDiscountsRemote(
            discountContract
        );
        SRTicketsDiscountsRemote.SenderAndTokenDiscountBuyer memory stdb;
        stdb.sender = sender;
        stdb.tockenDiscountBuyer = tokenDiscountBuyer[attendee.tokenDiscount][
            sender
        ];
        SRTicketsDiscountsRemote.DiscountResponse memory dr = dc
            .getDiscountView(
                stdb,
                discountCodeTickets[attendee.discountCode][attendee.ticket],
                discountCodes[attendee.discountCode],
                discountAddressTickets[attendee.sender][attendee.ticket],
                discountAddresses[attendee.sender],
                tokenDiscountTickets[attendee.tokenDiscount][attendee.ticket],
                tokenDiscounts[attendee.tokenDiscount],
                attendee.tokenDiscount
            );
        return dr;
    }

    /*   function getThing(address sender, Attendee memory attendee)
        public
        view
        returns (address)
    {
        //        return discountAddressTickets[attendee.sender][attendee.ticket];
        //return discountAddresses[0x70997970C51812dc3A010C7d01b50e0d17dc79C8];
        SRTicketsDiscountsRemote dc = SRTicketsDiscountsRemote(
            discountContract
        );
        return dc.SRTicketsAddress();
    }*/

    function updateAttendee(uint256 attendeeIndex, Attendee memory newAttendee)
        public
        payable
    {
        Attendee memory oldAttendee = getAttendee(msg.sender, attendeeIndex);

        require(
            oldAttendee.sender == msg.sender || msg.sender == owner,
            "not allowed"
        );
        if (
            oldAttendee.sender == msg.sender &&
            keccak256(abi.encodePacked(newAttendee.ticket)) !=
            keccak256(abi.encodePacked(oldAttendee.ticket))
        ) {
            if (tickets[newAttendee.ticket].price > oldAttendee.pricePaid) {
                require(
                    msg.value >
                        getPriceFromUSD(
                            tickets[newAttendee.ticket].price -
                                oldAttendee.pricePaid
                        ),
                    "new ticket more expensive"
                );
                tickets[newAttendee.ticket].used.increment();
                tickets[newAttendee.ticket].used.decrement();
                oldAttendee.pricePaid = tickets[newAttendee.ticket].price;
            }
        }
        setAttendee(
            attendeeIndex,
            newAttendee,
            oldAttendee,
            msg.sender,
            false,
            false
        );
    }

    function refund(
        address buyer,
        uint256 attendeeIndex,
        uint256 amount,
        bool cancel
    ) public onlyOwner {
        Attendee memory attendee = getAttendee(buyer, attendeeIndex);
        require(
            attendee.pricePaidInToken >= amount,
            "refund higher than paid price"
        );

        if (attendee.buyToken != address(0)) {
            IERC20(attendee.buyToken).safeTransfer(
                address(attendee.sender),
                amount
            );
            attendee.refunded = amount;
            attendee.cancelled = cancel;
            setAttendee(
                attendeeIndex,
                attendee,
                attendee,
                attendee.sender,
                false,
                true
            );
        } else {
            (bool ok, ) = address(buyer).call{value: amount}("");
            require(ok, "Failed");
            attendee.refunded = amount;
            attendee.cancelled = true;
            setAttendee(
                attendeeIndex,
                attendee,
                attendee,
                attendee.sender,
                false,
                true
            );
        }
    }

    function selfRefund(uint256 attendeeIndex) public nonReentrant {
        Attendee memory attendee = getAttendee(msg.sender, attendeeIndex);
        require(attendee.sender == msg.sender, "sender is not buyer");
        require(allowSelfRefund, "refund not possible");
        require(!attendee.cancelled, "already cancelled");
        require(
            tickets[attendee.ticket].endDate > block.timestamp,
            "refund not possible anymore"
        );
        uint256 amount = attendee.pricePaidInToken -
            (refundFee * attendee.pricePaidInToken) /
            100;
        if (attendee.buyToken != address(0)) {
            IERC20(attendee.buyToken).safeTransfer(
                address(attendee.sender),
                amount
            );
            attendee.refunded = amount;
            attendee.cancelled = true;
            setAttendee(
                attendeeIndex,
                attendee,
                attendee,
                attendee.sender,
                false,
                true
            );
        } else {
            (bool ok, ) = address(attendee.sender).call{value: amount}("");
            require(ok, "Failed");
            attendee.refunded = amount;
            attendee.cancelled = true;
            setAttendee(
                attendeeIndex,
                attendee,
                attendee,
                attendee.sender,
                false,
                true
            );
        }
    }

    function buyResellable(uint256 attendeeIndex, Attendee memory newAttendee)
        public
        payable
        nonReentrant
    {
        Attendee memory attendee = getAttendee(
            newAttendee.sender,
            attendeeIndex
        );
        bool canUpdate = false;
        require(attendee.allowResell, "not for sell");
        if (attendee.buyToken != address(0)) {
            require(
                IERC20(attendee.buyToken).transferFrom(
                    address(msg.sender),
                    address(this),
                    uint256((attendee.resellPrice * resellFee) / 100)
                ),
                "transfer failed"
            );
            require(
                IERC20(attendee.buyToken).transferFrom(
                    address(msg.sender),
                    address(attendee.sender),
                    uint256(
                        attendee.resellPrice -
                            (attendee.resellPrice * resellFee) /
                            100
                    )
                ),
                "transfer failed"
            );
            canUpdate = true;
        } else {
            require(msg.value == attendee.resellPrice, "not enough fund");
            (bool ok, ) = attendee.sender.call{
                value: attendee.resellPrice -
                    (attendee.resellPrice * resellFee) /
                    100
            }("");
            require(ok, "Failed");
            canUpdate = true;
        }
        if (canUpdate) {
            setAttendee(
                attendeeIndex,
                newAttendee,
                attendee,
                msg.sender,
                true,
                false
            );
        }
    }

    function withdraw(address _token, uint256 _amount) external onlyOwner {
        if (_token != address(0)) {
            IERC20(_token).safeTransfer(address(owner), _amount);
        } else {
            uint256 amount = address(this).balance;
            (bool ok, ) = owner.call{value: amount}("");
            require(ok, "Failed");
        }
    }

    function setOwner(address newOwner) public onlyOwner {
        owner = newOwner;
    }

    /*   function getAttendee(address sender, uint256 index)
        external
        view
        returns (Attendee memory)
    {
        //SRTicketsRemote str = SRTicketsRemote(sender);
        //Attendee memory x = str.attendees(sender, index);
        return attendees[sender][index];
    }
    */
}

