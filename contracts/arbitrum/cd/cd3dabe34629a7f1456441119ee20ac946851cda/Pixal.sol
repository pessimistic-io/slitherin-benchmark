// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.7.0 <0.9.0;

import "./ReentrancyGuard.sol";

struct Pixel {
    uint16 x;
    uint16 y;
    bytes3 color;
}

struct Details {
    uint16 x;
    uint16 y;
    uint200 timesPainted;
    bytes3 color;
    address author;
}

/* 
    @@@@@@@@@@@@@@      @@@@@@@@@@@@@/    ,@@@@@      @@@@@         @@@@@         @@@@@             
    @@@@      %@@@@/        &@@@@           @@@@@   @@@@@          @@@@@@@        @@@@@             
    @@@@       @@@@@        &@@@@            @@@@@ @@@@@          @@@@ @@@@       @@@@@             
    @@@@       @@@@@        &@@@@              @@@@@@@(          @@@@  @@@@&      @@@@@             
    @@@@@@@@@@@@@@          &@@@@              @@@@@@@          @@@@@   @@@@      @@@@@             
    @@@@((((*               &@@@@             @@@@@@@@@        (@@@@@@@@@@@@@     @@@@@             
    @@@@                    &@@@@           ,@@@@*  @@@@@      @@@@@@@@@@@@@@@    @@@@@             
    @@@@                @@@@@@@@@@@@@/     @@@@@     @@@@@    @@@@*       @@@@@   @@@@@@@@@@@@@@@@  
    @@@@                @@@@@@@@@@@@@/    @@@@@       @@@@@@ @@@@@         @@@@@  @@@@@@@@@@@@@@@@

    A two dimensional painting with 400x400 pixels, each pixel can have a specific color.
    Painting a pixel is free for the first time. 
    The price increases each time the pixel is painted.
 */
contract Pixal is ReentrancyGuard {
    uint256 constant CANVAS_SIZE = 400;

    address private owner;

    mapping(bytes => Details) pixels;

    event PixelPainted(uint16 x, uint16 y);

    constructor() {
        owner = msg.sender;
    }

    function id(uint256 x, uint256 y)
        internal
        view
        virtual
        returns (bytes memory)
    {
        return abi.encodePacked(x, y);
    }

    function price(uint256 timesPainted) internal pure returns (uint256) {
        if (timesPainted == 0) {
            return 0;
        } else if (timesPainted >= 11) {
            return 100000 ether;
        }

        return 0.00001 ether * 10**timesPainted;
    }

    /**
     * @dev Internal paint function, called by 'paint'.
     *
     *  Update a pixel details and pays the previous author, if any.
     *  Otherwise, instantiate the new pixel details.
     *  Returns the spent funds on this action.
     */
    function paintPixel(
        uint16 x,
        uint16 y,
        bytes3 color,
        uint256 funds
    ) internal returns (uint256) {
        require(x < CANVAS_SIZE && y < CANVAS_SIZE, "Coordinates out of range");

        bytes memory pixelId = id(x, y);
        uint256 timesPainted = pixels[pixelId].timesPainted;

        if (timesPainted > 0) {
            uint256 expense = price(timesPainted);

            require(
                funds >= expense && funds - expense >= 0,
                "Not enough funds"
            );

            payable(pixels[pixelId].author).transfer((expense * 3) / 4);

            pixels[pixelId].timesPainted++;
            pixels[pixelId].color = color;
            pixels[pixelId].author = msg.sender;

            return expense;
        } else {
            pixels[pixelId] = Details(x, y, 1, color, msg.sender);

            return 0;
        }
    }

    /**
     * @dev The painting function.
     *
     * It goes through the 'pixelsToPaint' array and tries to paint them with the received value.
     * Reverts if there's not enough funds to cover the expense.
     */
    function paint(Pixel[] memory pixelsToPaint) public payable nonReentrant {
        uint256 funds = msg.value;

        for (uint256 i = 0; i < pixelsToPaint.length; i++) {
            Pixel memory pixelToPaint = pixelsToPaint[i];

            funds -= paintPixel(
                pixelToPaint.x,
                pixelToPaint.y,
                pixelToPaint.color,
                funds
            );

            emit PixelPainted(pixelToPaint.x, pixelToPaint.y);
        }
    }

    /**
     * @dev The listing function.
     *
     * It returns a detailed list of pixels in-between the
     * two points (x0, y0) and (x1, y1).
     */
    function list(
        uint256 x0,
        uint256 y0,
        uint256 x1,
        uint256 y1
    ) public view virtual returns (Details[] memory) {
        require(x1 > x0 && y1 > y0);
        require(x0 >= 0 && y0 >= 0);
        require(x1 <= CANVAS_SIZE && y1 <= CANVAS_SIZE);

        Details[] memory result = new Details[]((x1 - x0) * (y1 - y0));
        uint256 index = 0;

        for (uint256 x = x0; x < x1; x++) {
            for (uint256 y = y0; y < y1; y++) {
                result[index] = pixels[id(x, y)];
                index++;
            }
        }

        return result;
    }

    function details(uint16 x, uint16 y)
        public
        view
        virtual
        returns (Details memory)
    {
        return pixels[id(x, y)];
    }

    function withdraw(uint256 funds) external {
        require(msg.sender == owner);

        payable(owner).transfer(funds);
    }

    receive() external payable {}
}

