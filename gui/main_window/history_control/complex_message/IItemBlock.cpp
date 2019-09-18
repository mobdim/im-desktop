#include "stdafx.h"

#include "IItemBlock.h"

UI_COMPLEX_MESSAGE_NS_BEGIN

IItemBlock::~IItemBlock() = default;

Data::Quote IItemBlock::getQuote() const
{
    return Data::Quote();
}

HistoryControl::StickerInfoSptr IItemBlock::getStickerInfo() const
{
    return HistoryControl::StickerInfoSptr();
}

UI_COMPLEX_MESSAGE_NS_END