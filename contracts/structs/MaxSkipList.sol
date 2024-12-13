// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library MaxSkipList {
    uint8 constant MAX_LEVEL = 8;
    uint8 constant LEVEL_MASK = uint8((1 << (MAX_LEVEL - 1)) - 1);
    uint256 constant BITMAP_MASK = 0xff;
    uint256 constant PRICE_MASK = ~BITMAP_MASK;

    struct Node {
        uint256 priceAndBitmap;  // price in upper 248 bits, bitmap in lower 8
        uint256[MAX_LEVEL] packedNextPrev;
    }

    struct List {
        uint256 head;
        uint256 length;
        uint256 nextId;
        uint256 freeListHead;
        mapping(uint256 => Node) nodes;
        mapping(uint256 => uint256) priceToId;
    }

    event NodeInserted(uint256 indexed nodeId, uint256 price);
    event NodeRemoved(uint256 indexed nodeId, uint256 price);

    function getLevel(uint256 nextId) internal pure returns (uint8) {
        uint8 level = 0;
        uint256 n = nextId;

        while (level < MAX_LEVEL - 1 && n % 2 == 0) {
            level++;
            n = n / 2;
        }
        return level;
    }

    function getPrice(uint256 priceAndBitmap) internal pure returns (uint256) {
        return priceAndBitmap >> 8;
    }

    function getLevelBitmap(uint256 priceAndBitmap) internal pure returns (uint8) {
        return uint8(priceAndBitmap & BITMAP_MASK);
    }

    function packPriceAndBitmap(uint256 price, uint8 bitmap) internal pure returns (uint256) {
        return (price << 8) | bitmap;
    }

    function packPointers(uint256 next, uint256 prev) internal pure returns (uint256) {
        require(next < (1 << 128) && prev < (1 << 128), "Pointer overflow");
        return (next << 128) | prev;
    }

    function unpackPointers(uint256 packed) internal pure returns (uint256 next, uint256 prev) {
        next = packed >> 128;
        prev = packed & ((1 << 128) - 1);
    }

    function insert(List storage self, uint256 price) internal returns (uint256 nodeId) {
        require(price > 0 && price < (1 << 248), "Invalid price");
        require(self.priceToId[price] == 0, "Price exists");

        if (self.freeListHead != 0) {
            nodeId = self.freeListHead;
            self.freeListHead = self.nodes[nodeId].packedNextPrev[0];
        } else {
            nodeId = self.nextId++;
        }

        uint8 newLevel = getLevel(nodeId);
        Node storage newNode = self.nodes[nodeId];
        newNode.priceAndBitmap = packPriceAndBitmap(price, uint8((1 << newLevel) - 1));

        uint256 current = self.head;
        uint256[MAX_LEVEL] memory updates;

        for (uint8 i = MAX_LEVEL - 1; i < MAX_LEVEL; i--) {
            while (true) {
                (uint256 next,) = unpackPointers(self.nodes[current].packedNextPrev[i]);
                if (next == 0 || getPrice(self.nodes[next].priceAndBitmap) < price) break;
                current = next;
            }
            updates[i] = current;
        }

        for (uint8 i = 0; i <= newLevel; i++) {
            if ((getLevelBitmap(newNode.priceAndBitmap) & (1 << i)) != 0) {
                uint256 updateNode = updates[i];
                (uint256 next,) = unpackPointers(self.nodes[updateNode].packedNextPrev[i]);

                newNode.packedNextPrev[i] = packPointers(next, updateNode);

                if (next != 0) {
                    self.nodes[next].packedNextPrev[i] = packPointers(next, nodeId);
                }

                self.nodes[updateNode].packedNextPrev[i] = packPointers(nodeId, updateNode);
            }
        }

        self.length++;
        self.priceToId[price] = nodeId;
        emit NodeInserted(nodeId, price);
    }

    function remove(List storage self, uint256 price) internal returns (bool) {
        uint256 nodeId = self.priceToId[price];
        require(nodeId != 0, "Not found");

        Node storage node = self.nodes[nodeId];

        for (uint8 i = 0; i < MAX_LEVEL; i++) {
            if ((getLevelBitmap(node.priceAndBitmap) & (1 << i)) != 0) {
                (uint256 next, uint256 prev) = unpackPointers(node.packedNextPrev[i]);

                if (prev != 0) {
                    self.nodes[prev].packedNextPrev[i] = packPointers(next, prev);
                }
                if (next != 0) {
                    self.nodes[next].packedNextPrev[i] = packPointers(next, prev);
                }
            }
        }

        // Add the node to the free list
        node.packedNextPrev[0] = self.freeListHead;
        self.freeListHead = nodeId;

        delete self.priceToId[price];
        self.length--;

        emit NodeRemoved(nodeId, price);
        return true;
    }

    function getHighestPrice(List storage self) internal view returns (uint256) {
        require(self.length > 0, "Empty list");
        (uint256 next,) = unpackPointers(self.nodes[self.head].packedNextPrev[MAX_LEVEL - 1]);
        return getPrice(self.nodes[next].priceAndBitmap);
    }

    function initialize(List storage self) internal {
        require(self.head == 0, "Already initialized");
        self.head = 0;
        self.nextId = 1;
        self.freeListHead = 0;
    }
}
