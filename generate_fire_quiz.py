# -*- coding: utf-8 -*-
"""
generate_fire_quiz.py
Generates quiz_font.hex and quiz_text.hex for V25 Fire Safety Promotion Quiz.
Optimized to <= 254 unique characters to fit in 8-bit text ROM and compact font ROM.
"""
import os
from PIL import Image, ImageFont, ImageDraw

# 19 screens total:
#   Screens 0..4: Questions 0..4 (5 Fire Safety Questions)
#   Screens 5..14: Feedback 0..4 (Correct then Incorrect for each Q)
#   Screens 15..18: Score Summary (0, 10, 20, 30 points)

SCREENS = [
    # ------------------ Screen 0: Question 0 ------------------
    [
        "【消防宣传】安全知识互动 (5抽3)",
        "发生火灾时，通用火灾报警电话是？",
        "   A. 110 (报警电话)",
        "   B. 119 (火警电话)",
        "   C. 120 (急救电话)",
        "KEY2:确认   KEY3:切换   KEY4:跳过"
    ],
    # ------------------ Screen 1: Question 1 ------------------
    [
        "【消防宣传】安全知识互动 (5抽3)",
        "火灾逃生遇到浓烟时，正确姿势是？",
        "   A. 直立身体快速跑",
        "   B. 弯腰低姿，湿毛巾捂口鼻",
        "   C. 乘普通电梯逃生",
        "KEY2:确认   KEY3:切换   KEY4:跳过"
    ],
    # ------------------ Screen 2: Question 2 ------------------
    [
        "【消防宣传】安全知识互动 (5抽3)",
        "电器电线起火时，首先应当如何处置？",
        "   A. 立即切断电源开关",
        "   B. 直接泼水灭火",
        "   C. 用湿毛巾覆盖",
        "KEY2:确认   KEY3:切换   KEY4:跳过"
    ],
    # ------------------ Screen 3: Question 3 ------------------
    [
        "【消防宣传】安全知识互动 (5抽3)",
        "使用灭火器灭火时，应对准火焰？",
        "   A. 火焰顶部",
        "   B. 火焰中部",
        "   C. 火焰根部",
        "KEY2:确认   KEY3:切换   KEY4:跳过"
    ],
    # ------------------ Screen 4: Question 4 ------------------
    [
        "【消防宣传】安全知识互动 (5抽3)",
        "关于安全疏散通道，正确做法是？",
        "   A. 堆放杂物占用",
        "   B. 保持畅通，严禁占用",
        "   C. 停放电动车充电",
        "KEY2:确认   KEY3:切换   KEY4:跳过"
    ],

    # ------------------ Screen 5: Q0 Correct ------------------
    [
        "【答题反馈】 消防安全常识",
        "★ 回答正确！得分 +10 分 ★",
        "你的选择: [   ]    正确答案: [   ]",
        "解析: 发生火灾第一时间拨打119火警电话。",
        "提示: 报警讲清起火地点，严禁谎报。",
        "[ 3秒后进入下一题，按KEY2继续 ]"
    ],
    # ------------------ Screen 6: Q0 Wrong ------------------
    [
        "【答题反馈】 消防安全常识",
        "✕ 回答错误！本题不得分",
        "你的选择: [   ]    正确答案: [   ]",
        "解析: 发生火灾第一时间拨打119火警电话。",
        "提示: 报警讲清起火地点，严禁谎报。",
        "[ 3秒后进入下一题，按KEY2继续 ]"
    ],

    # ------------------ Screen 7: Q1 Correct ------------------
    [
        "【答题反馈】 消防安全常识",
        "★ 回答正确！得分 +10 分 ★",
        "你的选择: [   ]    正确答案: [   ]",
        "解析: 浓烟向上，弯腰低姿贴近地面更安全。",
        "提示: 湿毛巾捂口鼻防烟，严禁乘电梯。",
        "[ 3秒后进入下一题，按KEY2继续 ]"
    ],
    # ------------------ Screen 8: Q1 Wrong ------------------
    [
        "【答题反馈】 消防安全常识",
        "✕ 回答错误！本题不得分",
        "你的选择: [   ]    正确答案: [   ]",
        "解析: 浓烟向上，弯腰低姿贴近地面更安全。",
        "提示: 湿毛巾捂口鼻防烟，严禁乘电梯。",
        "[ 3秒后进入下一题，按KEY2继续 ]"
    ],

    # ------------------ Screen 9: Q2 Correct ------------------
    [
        "【答题反馈】 消防安全常识",
        "★ 回答正确！得分 +10 分 ★",
        "你的选择: [   ]    正确答案: [   ]",
        "解析: 电器起火严禁泼水，应立即切断电源。",
        "提示: 电气火灾使用灭火器，防止发生触电。",
        "[ 3秒后进入下一题，按KEY2继续 ]"
    ],
    # ------------------ Screen 10: Q2 Wrong ------------------
    [
        "【答题反馈】 消防安全常识",
        "✕ 回答错误！本题不得分",
        "你的选择: [   ]    正确答案: [   ]",
        "解析: 电器起火严禁泼水，应立即切断电源。",
        "提示: 电气火灾使用灭火器，防止发生触电。",
        "[ 3秒后进入下一题，按KEY2继续 ]"
    ],

    # ------------------ Screen 11: Q3 Correct ------------------
    [
        "【答题反馈】 消防安全常识",
        "★ 回答正确！得分 +10 分 ★",
        "你的选择: [   ]    正确答案: [   ]",
        "解析: 灭火器对准火焰根部，快速灭火。",
        "提示: 拔掉开关，对准火焰根部压下灭火。",
        "[ 3秒后进入下一题，按KEY2继续 ]"
    ],
    # ------------------ Screen 12: Q3 Wrong ------------------
    [
        "【答题反馈】 消防安全常识",
        "✕ 回答错误！本题不得分",
        "你的选择: [   ]    正确答案: [   ]",
        "解析: 灭火器对准火焰根部，快速灭火。",
        "提示: 拔掉开关，对准火焰根部压下灭火。",
        "[ 3秒后进入下一题，按KEY2继续 ]"
    ],

    # ------------------ Screen 13: Q4 Correct ------------------
    [
        "【答题反馈】 消防安全常识",
        "★ 回答正确！得分 +10 分 ★",
        "你的选择: [   ]    正确答案: [   ]",
        "解析: 疏散通道是生命通道，严禁堆放杂物。",
        "提示: 电动车严禁停放充电，确保畅通。",
        "[ 3秒后进入下一题，按KEY2继续 ]"
    ],
    # ------------------ Screen 14: Q4 Wrong ------------------
    [
        "【答题反馈】 消防安全常识",
        "✕ 回答错误！本题不得分",
        "你的选择: [   ]    正确答案: [   ]",
        "解析: 疏散通道是生命通道，严禁堆放杂物。",
        "提示: 电动车严禁停放充电，确保畅通。",
        "[ 3秒后进入下一题，按KEY2继续 ]"
    ],

    # ------------------ Screen 15: Score 0 ------------------
    [
        "★ 消防宣传互动答题成绩单 ★",
        "最终得分: 0 分 (答对 0/3 题)",
        "综合评定: 【继续努力】",
        "认真学习消防安全常识，提升自救技能！",
        "关注消防生命至上，共建平安家园。",
        "[ 4秒后自动返回，或按任意键退出 ]"
    ],
    # ------------------ Screen 16: Score 10 ------------------
    [
        "★ 消防宣传互动答题成绩单 ★",
        "最终得分: 10 分 (答对 1/3 题)",
        "综合评定: 【掌握基础】",
        "掌握基础消防安全常识，继续提升自救技能！",
        "关注消防生命至上，共建平安家园。",
        "[ 4秒后自动返回，或按任意键退出 ]"
    ],
    # ------------------ Screen 17: Score 20 ------------------
    [
        "★ 消防宣传互动答题成绩单 ★",
        "最终得分: 20 分 (答对 2/3 题)",
        "综合评定: 【良好意识】",
        "具备良好消防安全意识，熟练掌握自救技能！",
        "关注消防生命至上，共建平安家园。",
        "[ 4秒后自动返回，或按任意键退出 ]"
    ],
    # ------------------ Screen 18: Score 30 ------------------
    [
        "★ 消防宣传互动答题成绩单 ★",
        "最终得分: 30 分 (答对 3/3 题)",
        "综合评定: 【消防之星】",
        "满分！消防安全常识全面，堪称安全模范！",
        "关注消防生命至上，共建平安家园。",
        "[ 4秒后自动返回，或按任意键退出 ]"
    ]
]

def main():
    # 1. Collect all unique non-space characters
    chars = []
    for screen in SCREENS:
        for line in screen:
            for ch in line:
                if ch not in chars and ch != ' ':
                    chars.append(ch)

    print(f"Total unique characters: {len(chars)}")
    assert len(chars) <= 254, f"Unique characters ({len(chars)}) exceeds 254 limit for 8-bit text ROM!"

    # Map char -> glyph index (0 .. len(chars)-1)
    char_to_id = {ch: idx for idx, ch in enumerate(chars)}

    # 2. Render each glyph using SimSun 16pt font
    font_path = os.path.join(os.environ['WINDIR'], 'Fonts', 'simsun.ttc')
    font = ImageFont.truetype(font_path, 16)

    glyph_bitmaps = []
    for ch in chars:
        im = Image.new('1', (16, 16), 0)
        draw = ImageDraw.Draw(im)
        draw.text((0, 0), ch, font=font, fill=1)
        
        # Extract 16 rows of 16-bit words
        bitmap = []
        for y in range(16):
            word = 0
            for x in range(16):
                if im.getpixel((x, y)):
                    word |= (1 << (15 - x))
            bitmap.append(word)
        glyph_bitmaps.append(bitmap)

    # 3. Generate quiz_font.hex
    # Each glyph: 16 words in hex (4 hex digits per line)
    font_hex_lines = []
    for g_idx, bitmap in enumerate(glyph_bitmaps):
        for word in bitmap:
            font_hex_lines.append(f"{word:04x}")

    print(f"Total active font lines (16 per glyph): {len(font_hex_lines)}")
    # Pad font to 4096 lines (power of 2 for direct BRAM9K hardware mapping)
    while len(font_hex_lines) < 4096:
        font_hex_lines.append("0000")
    print(f"Padded font lines for 4K BRAM: {len(font_hex_lines)}")

    # 4. Generate quiz_text.hex
    # Each screen: 6 lines * 32 characters = 192 bytes
    # Non-space chars map to glyph_id, space / padding maps to 0xFF
    text_hex_lines = []
    for s_idx, screen in enumerate(SCREENS):
        for l_idx in range(6):
            line_str = screen[l_idx] if l_idx < len(screen) else ""
            for c_idx in range(32):
                if c_idx < len(line_str) and line_str[c_idx] != ' ':
                    ch = line_str[c_idx]
                    g_id = char_to_id[ch]
                    text_hex_lines.append(f"{g_id:02x}")
                else:
                    text_hex_lines.append("ff")

    print(f"Total screens: {len(SCREENS)}, active text bytes: {len(text_hex_lines)}")
    assert len(text_hex_lines) == 19 * 192, f"Expected {19*192}, got {len(text_hex_lines)}"
    # Pad text to 4096 lines (power of 2 for direct BRAM9K hardware mapping)
    while len(text_hex_lines) < 4096:
        text_hex_lines.append("ff")
    print(f"Padded text bytes for 4K BRAM: {len(text_hex_lines)}")

    # 5. Write outputs relative to this submission directory so the tool is portable.
    project_root = os.path.dirname(os.path.abspath(__file__))
    dest_dirs = [
        os.path.join(project_root, "02_FPGA_PROJECT", "src", "user_source", "hdl_source"),
        os.path.join(project_root, "02_FPGA_PROJECT", "src", "td_project"),
    ]

    for d in dest_dirs:
        os.makedirs(d, exist_ok=True)
        with open(os.path.join(d, "quiz_font.hex"), "w", encoding="ascii") as f:
            for l in font_hex_lines:
                f.write(l + "\n")
        with open(os.path.join(d, "quiz_text.hex"), "w", encoding="ascii") as f:
            for l in text_hex_lines:
                f.write(l + "\n")
        print(f"Saved hex files to {d}")

    print(f"Fire Safety Quiz Hex Generation Complete! Total Glyphs: {len(chars)}, Font Lines: {len(font_hex_lines)}")

if __name__ == '__main__':
    main()
