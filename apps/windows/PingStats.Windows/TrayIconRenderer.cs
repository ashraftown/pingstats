using System.Drawing;
using System.Drawing.Drawing2D;

namespace PingStats;

internal static class TrayIconRenderer
{
    internal const int IconWidth = 64;
    internal const int IconHeight = 64;
    internal const int ThreeDigitDotSize = 6;

    private const int DotSize = 7;
    private const int DotY = 0;
    private const int TwoDigitFontSize = 48;
    private const int ThreeDigitFontSize = 40;
    private const float ThreeDigitHorizontalScale = 0.8f;
    private static readonly StringFormat StringFormat = StringFormat.GenericTypographic;

    internal static Bitmap Render(string displayText, Color dotColor, Color textColor)
    {
        var isThreeDigit = displayText.Length == 3;
        var dotSize = isThreeDigit ? ThreeDigitDotSize : DotSize;

        var bitmap = new Bitmap(IconWidth, IconHeight);
        using var g = Graphics.FromImage(bitmap);
        g.SmoothingMode = SmoothingMode.AntiAlias;
        g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.AntiAlias;
        g.Clear(Color.Transparent);

        var dotX = (IconWidth - dotSize) / 2;
        using (var brush = new SolidBrush(dotColor))
        {
            g.FillEllipse(brush, dotX, DotY, dotSize, dotSize);
        }

        var fontSize = isThreeDigit ? ThreeDigitFontSize : TwoDigitFontSize;
        using var font = new Font("Consolas", fontSize, FontStyle.Regular, GraphicsUnit.Pixel);
        using var textBrush = new SolidBrush(textColor);
        var textSize = g.MeasureString(displayText, font, int.MaxValue, StringFormat);
        var textX = (IconWidth - textSize.Width) / 2;
        var textY = DotY + dotSize;

        var textState = g.Save();
        try
        {
            if (isThreeDigit)
            {
                var horizontalOffset = IconWidth * (1f - ThreeDigitHorizontalScale) / 2f;
                using var transform = new Matrix(
                    ThreeDigitHorizontalScale, 0,
                    0, 1,
                    horizontalOffset, 0);
                g.Transform = transform;
            }

            g.DrawString(displayText, font, textBrush, textX, textY, StringFormat);
        }
        finally
        {
            g.Restore(textState);
        }

        return bitmap;
    }
}
