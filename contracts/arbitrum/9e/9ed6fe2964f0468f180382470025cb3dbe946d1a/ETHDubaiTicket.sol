pragma experimental ABIEncoderV2;
pragma solidity ^0.8.10;
//SPDX-License-Identifier: MIT

import "./ERC721URIStorage.sol";
import "./Counters.sol";
import "./Address.sol";
import "./EnumerableSet.sol";
import "./HexStrings.sol";
import "./ToColor.sol";
import "./SVG721.sol";

// GET LISTED ON OPENSEA: https://testnets.opensea.io/get-listed/step-two
contract RenderSVGContractABI {
    function renderToken(
        string memory c1,
        string memory c2,
        string memory c3,
        string memory c4,
        string memory c5
    ) public pure returns (string memory) {}

    function generateSVGofTokenById(
        string memory preEvent1,
        string memory rsca,
        string memory id,
        string memory telegram
    ) public pure returns (string memory) {}
}

contract ETHDubaiTicket is ERC721URIStorage {
    using Strings for uint256;
    using HexStrings for uint160;
    using ToColor for bytes3;
    using Counters for Counters.Counter;
    using EnumerableSet for EnumerableSet.AddressSet;
    address rscaAddr;

    Counters.Counter private _tokenIds;
    address payable public owner;
    Settings public settings;
    event Log(address indexed sender, string message);
    event Lint(uint256 indexed tokenId, string message);
    event LMintId(address indexed sender, uint256 id, string message);
    event LAttendeeInfo(
        uint256 indexed id,
        AttendeeInfo attendeeInfo,
        string message
    );
    event LTicketAction(uint256 indexed id, bool value, string message);
    event LResellable(
        uint256 indexed id,
        Resellable resellable,
        string message
    );
    event LTicketSettings(
        TicketSettings indexed ticketSettings,
        string message
    );
    event LMint(MintLog indexed mintLog, string message);
    event LResell(ResellLog indexed resellLog, string message);

    constructor() ERC721("ETHDubaiTicket", "ETHDUBAI") {
        //constructor() ERC721("TESTETHDT", "EBI") {
        emit Log(msg.sender, "created");
        owner = payable(msg.sender);
        settings.maxMint = 50;
        rscaAddr = 0x5eb3Bc0a489C5A8288765d2336659EbCA68FCd00;

        settings.ticketSettings = TicketSettings("early");

        settings.ticketOptionPrices["conference"] = 0.07 ether;
        settings.ticketOptionPrices["workshop"] = 2 ether;
        settings.ticketOptionPrices["workshop1AndPreParty"] = 0.12 ether;
        settings.ticketOptionPrices["workshop2AndPreParty"] = 0.12 ether;
        settings.ticketOptionPrices["workshop3AndPreParty"] = 0.12 ether;
        settings.ticketOptionPrices["workshop4AndPreParty"] = 0.12 ether;
        settings.ticketOptionPrices["hotelConference"] = 0.17 ether;
        settings.ticketOptionPrices["hotel2Conference"] = 0.3 ether;
        settings.ticketOptionPrices["hotelWorkshops1AndPreParty"] = 0.4 ether;
        settings.ticketOptionPrices["hotelWorkshops2AndPreParty"] = 0.4 ether;
        settings.ticketOptionPrices["hotelWorkshops3AndPreParty"] = 0.4 ether;
        settings.ticketOptionPrices["hotelWorkshops4AndPreParty"] = 0.4 ether;
        settings.ticketOptionPrices["hotel2Workshops1AndPreParty"] = 0.5 ether;
        settings.ticketOptionPrices["hotel2Workshops2AndPreParty"] = 0.5 ether;
        settings.ticketOptionPrices["hotel2Workshops3AndPreParty"] = 0.5 ether;
        settings.ticketOptionPrices["hotel2Workshops4AndPreParty"] = 0.5 ether;
        settings.workshops["workshop1AndPreParty"] = true;
        settings.workshops["workshop2AndPreParty"] = true;
        settings.workshops["workshop3AndPreParty"] = true;
        settings.workshops["workshop4AndPreParty"] = true;
        settings.workshops["hotelWorkshops1AndPreParty"] = true;
        settings.workshops["hotelWorkshops2AndPreParty"] = true;
        settings.workshops["hotelWorkshops3AndPreParty"] = true;
        settings.workshops["hotelWorkshops4AndPreParty"] = true;
        settings.workshops["hotel2Workshops1AndPreParty"] = true;
        settings.workshops["hotel2Workshops2AndPreParty"] = true;
        settings.workshops["hotel2Workshops3AndPreParty"] = true;
        settings.workshops["hotel2Workshops4AndPreParty"] = true;
    }

    struct Resellable {
        bool isResellable;
        uint256 price;
    }

    struct Discount {
        string[] ticketOptions;
        uint256 amount;
        uint256 qty;
        Counters.Counter used;
    }

    struct TicketSettings {
        string name;
    }

    struct Settings {
        TicketSettings ticketSettings;
        uint256 maxMint;
        mapping(string => bool) workshops;
        mapping(string => uint256) ticketOptionPrices;
    }
    struct AttendeeInfo {
        string email;
        string fname;
        string lname;
        string twitter;
        string bio;
        string job;
        string company;
        string workshop;
        string tshirt;
        string telegram;
    }

    struct Colors {
        bytes3 color1;
        bytes3 color2;
        bytes3 color3;
        bytes3 color4;
        bytes3 color5;
    }

    struct MintLog {
        Discount discount;
        TicketSettings ticketSettings;
        address buyer;
        uint256 amount;
        uint256 tokenId;
        string ticketOption;
    }

    struct ResellLog {
        address from;
        address to;
        uint256 tokenId;
        uint256 amount;
    }

    struct MintInfo {
        AttendeeInfo attendeeInfo;
        string ticketCode;
        string ticketOption;
        string specialStatus;
        Resellable resellable;
    }

    mapping(uint256 => AttendeeInfo) public _idToAttendeeInfo;
    mapping(uint256 => string) public _idToTicketCode;
    mapping(uint256 => Resellable) public _idToTicketResellable;
    mapping(uint256 => bool) public _idToScanned;
    mapping(uint256 => bool) public _idToCanceled;
    mapping(uint256 => Colors) private _idToColors;
    mapping(uint256 => string) public _idToTicketOption;
    mapping(uint256 => string) public _idToSpecialStatus;
    EnumerableSet.AddressSet private daosAddresses;
    mapping(address => uint256) public daosQty;
    mapping(address => Counters.Counter) public daosUsed;
    mapping(address => uint256) public daosMinBalance;
    mapping(address => uint256) public daosDiscount;
    mapping(address => uint256) public daosMinTotal;
    mapping(address => uint256) public daosMaxTotal;
    mapping(address => Discount) public discounts;

    function setDiscount(
        address buyer,
        string[] memory newDiscounts,
        uint256 amount,
        uint256 qty
    ) public returns (bool) {
        require(msg.sender == owner, "only owner");
        Discount memory d;
        d.ticketOptions = newDiscounts;
        d.qty = qty;
        d.amount = amount;
        discounts[buyer] = d;
        return true;
    }

    function setRsca(address addr) public {
        rscaAddr = addr;
    }

    function setMaxMint(uint256 max) public returns (uint256) {
        require(msg.sender == owner, "only owner");
        settings.maxMint = max;
        emit Lint(max, "setMaxMint");
        return max;
    }

    function markAsScannedCanceld(
        uint256 id,
        bool scan,
        bool canceled
    ) public returns (bool) {
        require(msg.sender == owner, "only owner");
        _idToScanned[id] = scan;
        _idToCanceled[id] = canceled;
        emit LTicketAction(id, scan, "scan");
        emit LTicketAction(id, canceled, "cancel");
        return scan;
    }

    function setDao(
        address dao,
        uint256 qty,
        uint256 discount,
        uint256 minBalance,
        uint256 minTotal,
        uint256 maxTotal
    ) public returns (bool) {
        require(msg.sender == owner, "only owner");
        require(Address.isContract(dao), "nc");
        if (!daosAddresses.contains(dao)) daosAddresses.add(dao);
        daosQty[dao] = qty;
        daosMinBalance[dao] = minBalance;
        daosDiscount[dao] = discount;
        daosMinTotal[dao] = minTotal;
        daosMaxTotal[dao] = maxTotal;
        return true;
    }

    function setTicketOption(string memory name, uint256 amount)
        public
        returns (bool)
    {
        require(msg.sender == owner, "only owner");
        settings.ticketOptionPrices[name] = amount;
        return true;
    }

    function setTicketSettings(string memory name) public returns (bool) {
        require(msg.sender == owner, "only owner");
        settings.ticketSettings.name = name;
        emit LTicketSettings(settings.ticketSettings, "setTicketSettings");
        return true;
    }

    function setResellable(
        uint256 id,
        bool isResellable,
        uint256 price
    ) public returns (bool) {
        require(msg.sender == this.ownerOf(id), "only owner");
        Resellable memory resellable = Resellable(isResellable, price);
        _idToTicketResellable[id] = resellable;
        emit LResellable(id, resellable, "setResellable");
        return true;
    }

    function updateAttendeeInfo(uint256 id, AttendeeInfo memory attendeeInfo)
        public
        returns (bool)
    {
        require(
            msg.sender == owner || msg.sender == this.ownerOf(id),
            "only contract or ticket owner"
        );
        _idToAttendeeInfo[id] = attendeeInfo;
        emit LAttendeeInfo(id, attendeeInfo, "updateAttendeeInfo");
        return true;
    }

    function resell(uint256 tokenId) public payable virtual {
        Resellable memory resellable = _idToTicketResellable[tokenId];
        require(resellable.isResellable, "not for sale");
        require(msg.value >= resellable.price, "price too low");
        uint256 amount = msg.value;
        uint256 fee = amount / 50;
        uint256 resellerAmount = amount - fee;
        address payable reseller = payable(address(ownerOf(tokenId)));
        reseller.transfer(resellerAmount);
        _transfer(ownerOf(tokenId), msg.sender, tokenId);
        resellable.isResellable = false;
        _idToTicketResellable[tokenId] = resellable;
        ResellLog memory resellL = ResellLog(
            ownerOf(tokenId),
            msg.sender,
            tokenId,
            amount
        );
        emit LResell(resellL, "resell");
    }

    function getDiscount(
        address sender,
        string memory ticketOption,
        uint256 ticketsLength
    ) public returns (uint256[2] memory) {
        Discount memory discount = discounts[sender];
        uint256 amount = discounts[sender].amount;
        uint256 total = 0;
        bool hasDiscount = false;
        total = total + settings.ticketOptionPrices[ticketOption];
        if (
            amount > 0 &&
            discounts[sender].used.current() + ticketsLength <
            discounts[sender].qty
        ) {
            for (uint256 j = 0; j < discount.ticketOptions.length; j++) {
                string memory a = discount.ticketOptions[j];
                string memory b = ticketOption;
                if (
                    (keccak256(abi.encodePacked((a))) ==
                        keccak256(abi.encodePacked((b))))
                ) {
                    hasDiscount = true;
                    discounts[sender].used.increment();
                }
            }
            if (!hasDiscount) {
                amount = 0;
            }
        }
        return [amount, total];
    }

    function getDiscountView(
        address sender,
        string memory ticketOption,
        uint256 ticketsLength
    ) public view returns (uint256[2] memory) {
        Discount memory discount = discounts[sender];
        uint256 amount = discounts[sender].amount;
        uint256 total = 0;
        bool hasDiscount = false;
        total = total + settings.ticketOptionPrices[ticketOption];
        if (
            amount > 0 &&
            discounts[sender].used.current() + ticketsLength <
            discounts[sender].qty
        ) {
            for (uint256 j = 0; j < discount.ticketOptions.length; j++) {
                string memory a = discount.ticketOptions[j];
                string memory b = ticketOption;
                if (
                    (keccak256(abi.encodePacked((a))) ==
                        keccak256(abi.encodePacked((b))))
                ) {
                    hasDiscount = true;
                }
            }
            if (!hasDiscount) {
                amount = 0;
            }
        } else {
            amount = 0;
        }
        return [amount, total];
    }

    function getDaoDiscountView(uint256 amount, uint256 ticketsLength)
        internal
        view
        returns (uint256[3] memory)
    {
        uint256 minTotal = 0;
        uint256 maxTotal = 0;
        if (amount == 0) {
            uint256 b = 0;

            for (uint256 j = 0; j < daosAddresses.length(); j++) {
                address dao = daosAddresses.at(j);
                if (
                    daosDiscount[dao] > 0 &&
                    daosUsed[dao].current() + ticketsLength < daosQty[dao]
                ) {
                    ERC721 token = ERC721(dao);
                    b = token.balanceOf(msg.sender);
                    if (b > daosMinBalance[dao] && amount == 0) {
                        amount = daosDiscount[dao];
                        minTotal = daosMinTotal[dao];
                        maxTotal = daosMaxTotal[dao];
                    }
                }
            }
        }
        return [amount, minTotal, maxTotal];
    }

    function getDaoDiscount(uint256 amount, uint256 ticketsLength)
        internal
        returns (uint256[3] memory)
    {
        uint256 minTotal = 0;
        uint256 maxTotal = 0;
        if (amount == 0) {
            uint256 b = 0;

            for (uint256 j = 0; j < daosAddresses.length(); j++) {
                address dao = daosAddresses.at(j);
                if (
                    daosDiscount[dao] > 0 &&
                    daosUsed[dao].current() + ticketsLength < daosQty[dao]
                ) {
                    ERC721 token = ERC721(dao);
                    b = token.balanceOf(msg.sender);
                    if (b > daosMinBalance[dao] && amount == 0) {
                        amount = daosDiscount[dao];
                        daosUsed[dao].increment();
                        minTotal = daosMinTotal[dao];
                        maxTotal = daosMaxTotal[dao];
                    }
                }
            }
        }
        return [amount, minTotal, maxTotal];
    }

    function getPrice(
        address sender,
        string memory ticketOption,
        uint256 ticketsLength
    ) public returns (uint256) {
        uint256[2] memory amountAndTotal = getDiscount(
            sender,
            ticketOption,
            ticketsLength
        );
        uint256 total = amountAndTotal[1];
        uint256[3] memory amountAndMinTotal = getDaoDiscount(
            amountAndTotal[0],
            ticketsLength
        );
        require(total > 0, "total = 0");
        if (amountAndTotal[0] > 0) {
            total = total - ((total * amountAndTotal[0]) / 100);
        } else if (
            amountAndMinTotal[0] > 0 &&
            amountAndMinTotal[1] <= total &&
            amountAndMinTotal[2] >= total
        ) {
            total = total - ((total * amountAndMinTotal[0]) / 100);
        }

        return total;
    }

    function getPriceView(
        address sender,
        string memory ticketOption,
        uint256 ticketsLength
    ) public view returns (uint256) {
        uint256[2] memory amountAndTotal = getDiscountView(
            sender,
            ticketOption,
            ticketsLength
        );
        uint256 total = amountAndTotal[1];
        uint256[3] memory amountAndMinTotal = getDaoDiscountView(
            amountAndTotal[0],
            ticketsLength
        );
        require(total > 0, "total = 0");
        if (amountAndTotal[0] > 0) {
            total = total - ((total * amountAndTotal[0]) / 100);
        } else if (
            amountAndMinTotal[0] > 0 &&
            amountAndMinTotal[1] <= total &&
            amountAndMinTotal[2] >= total
        ) {
            total = total - ((total * amountAndMinTotal[0]) / 100);
        }

        return total;
    }

    function genColor(bytes32 pr) internal pure returns (bytes3) {
        bytes3 color = bytes2(pr[0]) |
            (bytes2(pr[1]) >> 8) |
            (bytes3(pr[2]) >> 16);
        return color;
    }

    function genPredictable(
        address sender,
        address that,
        bytes32 blockNum,
        string memory attendeeProp
    ) internal pure returns (bytes32) {
        return
            keccak256(abi.encodePacked(blockNum, sender, that, attendeeProp));
    }

    function processMintIntem(MintInfo memory mintInfo, address sender)
        internal
        returns (uint256)
    {
        uint256 total;
        Discount memory discount = discounts[sender];

        _tokenIds.increment();

        uint256 id = _tokenIds.current();
        _mint(sender, id);
        bytes32 predictableRandom1 = genPredictable(
            sender,
            address(this),
            blockhash(block.number + 1),
            mintInfo.attendeeInfo.email
        );

        _idToColors[id].color1 = genColor(predictableRandom1);

        bytes32 predictableRandom2 = genPredictable(
            sender,
            address(this),
            blockhash(block.number + 2),
            mintInfo.attendeeInfo.telegram
        );

        _idToColors[id].color2 = genColor(predictableRandom2);

        bytes32 predictableRandom3 = genPredictable(
            sender,
            address(this),
            blockhash(block.number + 3),
            mintInfo.attendeeInfo.fname
        );

        _idToColors[id].color3 = genColor(predictableRandom3);

        bytes32 predictableRandom4 = genPredictable(
            sender,
            address(this),
            blockhash(block.number + 4),
            mintInfo.attendeeInfo.lname
        );

        _idToColors[id].color4 = genColor(predictableRandom4);

        bytes32 predictableRandom5 = genPredictable(
            sender,
            address(this),
            blockhash(block.number + 50),
            "foo5"
        );

        _idToColors[id].color5 = genColor(predictableRandom5);

        _idToAttendeeInfo[id] = mintInfo.attendeeInfo;
        _idToTicketCode[id] = mintInfo.ticketCode;
        _idToTicketResellable[id] = mintInfo.resellable;
        _idToScanned[id] = false;
        _idToCanceled[id] = false;
        _idToTicketOption[id] = mintInfo.ticketOption;
        _idToSpecialStatus[id] = mintInfo.specialStatus;

        MintLog memory mintLog = MintLog(
            discount,
            settings.ticketSettings,
            sender,
            total,
            id,
            mintInfo.ticketOption
        );
        emit LMint(mintLog, "mintItem");
        return id;
    }

    function totalPrice(MintInfo[] memory mIs) public view returns (uint256) {
        uint256 t = 0;
        for (uint256 i = 0; i < mIs.length; i++) {
            t += getPriceView(msg.sender, mIs[i].ticketOption, i);
        }
        return t;
    }

    function totalPriceInternal(MintInfo[] memory mIs)
        internal
        returns (uint256)
    {
        uint256 t = 0;
        for (uint256 i = 0; i < mIs.length; i++) {
            t += getPrice(msg.sender, mIs[i].ticketOption, i);
        }
        return t;
    }

    function mintItem(MintInfo[] memory mintInfos)
        public
        payable
        returns (string memory)
    {
        require(
            _tokenIds.current() + mintInfos.length <= settings.maxMint,
            "sold out"
        );
        uint256 total = totalPriceInternal(mintInfos);

        require(msg.value >= total, "price too low");
        string memory ids = "";
        for (uint256 i = 0; i < mintInfos.length; i++) {
            require(
                keccak256(abi.encodePacked(mintInfos[i].specialStatus)) ==
                    keccak256(abi.encodePacked("")) ||
                    msg.sender == owner,
                "only owner"
            );
            uint256 mintedId = processMintIntem(mintInfos[i], msg.sender);

            emit LMintId(msg.sender, mintedId, "Minted Id");
        }
        return ids;
    }

    function mintItemNoDiscount(MintInfo[] memory mintInfos)
        public
        payable
        returns (string memory)
    {
        require(
            _tokenIds.current() + mintInfos.length <= settings.maxMint,
            "sold out"
        );
        uint256 total = 0;
        string memory ids = "";
        for (uint256 i = 0; i < mintInfos.length; i++) {
            require(
                keccak256(abi.encodePacked(mintInfos[i].specialStatus)) ==
                    keccak256(abi.encodePacked("")) ||
                    msg.sender == owner,
                "only owner"
            );
            uint256 mintedId = processMintIntem(mintInfos[i], msg.sender);
            total += settings.ticketOptionPrices[mintInfos[i].ticketOption];
            emit LMintId(msg.sender, mintedId, "Minted Id");
        }
        require(msg.value >= total, "price too low");

        return ids;
    }

    function cmpStr(string memory idopt, string memory opt)
        internal
        pure
        returns (bool)
    {
        return (keccak256(abi.encodePacked((idopt))) ==
            keccak256(abi.encodePacked((opt))));
    }

    function generateSVGofTokenById(uint256 id)
        internal
        view
        returns (string memory)
    {
        string memory preEvent1;
        if (cmpStr(_idToTicketOption[id], "hotelConference")) {
            preEvent1 = "hotel";
        }

        if (settings.workshops[_idToTicketOption[id]]) {
            preEvent1 = _idToTicketOption[id];
        }
        if (!cmpStr(_idToSpecialStatus[id], "")) {
            preEvent1 = _idToSpecialStatus[id];
        }

        string memory idstr = uint2str(id);
        RenderSVGContractABI rsca;
        rsca = RenderSVGContractABI(rscaAddr);
        string memory svg = rsca.generateSVGofTokenById(
            preEvent1,
            renderTokenById(id),
            idstr,
            _idToAttendeeInfo[id].telegram
        );

        return svg;
    }

    function renderTokenById(uint256 id) private view returns (string memory) {
        RenderSVGContractABI rsca;
        rsca = RenderSVGContractABI(rscaAddr);
        string memory c1 = _idToColors[id].color1.toColor();
        string memory c2 = _idToColors[id].color2.toColor();
        string memory c3 = _idToColors[id].color3.toColor();
        string memory c4 = _idToColors[id].color4.toColor();
        string memory c5 = _idToColors[id].color5.toColor();
        string memory render = rsca.renderToken(c1, c2, c3, c4, c5);

        return render;
    }

    function uint2str(uint256 _i)
        internal
        pure
        returns (string memory _uintAsString)
    {
        if (_i == 0) {
            return "0";
        }
        uint256 j = _i;
        uint256 len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint256 k = len;
        while (_i != 0) {
            k = k - 1;
            uint8 temp = (48 + uint8(_i - (_i / 10) * 10));
            bytes1 b1 = bytes1(temp);
            bstr[k] = b1;
            _i /= 10;
        }
        return string(bstr);
    }

    function compareStrings(string memory a, string memory b)
        internal
        pure
        returns (bool)
    {
        return (keccak256(abi.encodePacked((a))) ==
            keccak256(abi.encodePacked((b))));
    }

    function tokenURI(uint256 id) public view override returns (string memory) {
        require(_exists(id), "not exist");
        string memory name = string(
            abi.encodePacked("ETHDubai Ticket #", id.toString())
        );
        string memory dsc = string(
            abi.encodePacked("ETHDubai 2022 conference ticket.")
        );
        string memory image = generateSVGofTokenById(id);
        //rj = RenderSVGABI(renderJson);
        //string memory img = rj.convert(image);
        return SVG721.metadata(name, dsc, image);
    }

    function withdraw() public {
        uint256 amount = address(this).balance;

        (bool ok, ) = owner.call{value: amount}("");
        require(ok, "Failed");
        emit Lint(amount, "withdraw");
    }
}

