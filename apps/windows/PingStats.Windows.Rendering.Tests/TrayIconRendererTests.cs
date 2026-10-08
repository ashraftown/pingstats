using System.Drawing;
using Xunit;

namespace PingStats.Tests;

public class TrayIconRendererTests
{
    [Theory]
    [InlineData("100")]
    [InlineData("999")]
    public void Three_digit_value_fits_and_stays_clear_of_the_status_dot(string value)
    {
        using var bitmap = TrayIconRenderer.Render(value, Color.Lime, Color.White);
        var textPixels = FindTextPixels(bitmap);

        Assert.NotEmpty(textPixels);
        Assert.All(textPixels, pixel => Assert.True(pixel.Y >= TrayIconRenderer.ThreeDigitDotSize));
        Assert.True(textPixels.Min(pixel => pixel.X) > 0);
        Assert.True(textPixels.Max(pixel => pixel.X) < TrayIconRenderer.IconWidth - 1);
        Assert.True(textPixels.Max(pixel => pixel.Y) < TrayIconRenderer.IconHeight - 1);

        for (var digit = 0; digit < 3; digit++)
        {
            var left = digit * TrayIconRenderer.IconWidth / 3;
            var right = (digit + 1) * TrayIconRenderer.IconWidth / 3;
            Assert.Contains(textPixels, pixel => pixel.X >= left && pixel.X < right);
        }

        Assert.Contains(
            Enumerable.Range(0, bitmap.Width).SelectMany(x => Enumerable.Range(0, TrayIconRenderer.ThreeDigitDotSize)
                .Select(y => bitmap.GetPixel(x, y))),
            pixel => pixel.A > 0 && pixel.G > pixel.R && pixel.G > pixel.B);
    }

    private static List<Point> FindTextPixels(Bitmap bitmap)
    {
        var points = new List<Point>();
        for (var y = 0; y < bitmap.Height; y++)
        for (var x = 0; x < bitmap.Width; x++)
        {
            var pixel = bitmap.GetPixel(x, y);
            if (pixel.A > 0 && pixel.R == pixel.G && pixel.G == pixel.B)
                points.Add(new Point(x, y));
        }

        return points;
    }
}
