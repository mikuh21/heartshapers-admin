let activeLocks = 0;
let originalStyles = null;
let originalScrollY = 0;

export function lockBodyScroll() {
  if (activeLocks === 0) {
    const bodyStyle = document.body.style;
    originalScrollY = window.scrollY;
    originalStyles = {
      overflow: bodyStyle.overflow,
      paddingRight: bodyStyle.paddingRight,
      position: bodyStyle.position,
      top: bodyStyle.top,
      width: bodyStyle.width
    };
    const scrollbarWidth = window.innerWidth - document.documentElement.clientWidth;
    bodyStyle.overflow = "hidden";
    bodyStyle.position = "fixed";
    bodyStyle.top = `-${originalScrollY}px`;
    bodyStyle.width = "100%";
    if (scrollbarWidth > 0) bodyStyle.paddingRight = `${scrollbarWidth}px`;
  }
  activeLocks += 1;

  let released = false;
  return function releaseBodyScroll() {
    if (released) return;
    released = true;
    activeLocks = Math.max(0, activeLocks - 1);
    if (activeLocks > 0 || !originalStyles) return;
    const bodyStyle = document.body.style;
    bodyStyle.overflow = originalStyles.overflow;
    bodyStyle.paddingRight = originalStyles.paddingRight;
    bodyStyle.position = originalStyles.position;
    bodyStyle.top = originalStyles.top;
    bodyStyle.width = originalStyles.width;
    originalStyles = null;
    window.scrollTo(0, originalScrollY);
  };
}
